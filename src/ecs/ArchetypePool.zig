const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PR = @import("PoolRegistry.zig");

const ArrayList = std.ArrayList;
const Entity = EM.Entity;

fn ComponentArrayStorage(comptime pool_components: []const CR.ComponentName, comptime optimize: bool) type {
    var fields: [pool_components.len + 1]std.builtin.Type.StructField = undefined;

    fields[0] = std.builtin.Type.StructField{
        .name = "entities",
        .type = ArrayList(Entity),
        .alignment = @alignOf(ArrayList(Entity)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    inline for(pool_components, 1..) |component, i| {
        const name = @tagName(component);    
        const T = CR.getTypeByName(component);
        const storage_type = if(optimize) ?ArrayList(T) else ?*ArrayList(T); 

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = storage_type,
            .alignment = @alignOf(storage_type),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }


    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn ArchetypePool(comptime pool_components: []const CR.ComponentName, comptime optimize: bool) type {
    const storage_type = ComponentArrayStorage(pool_components, optimize);

    const component_set = blk: {
        var set = std.EnumSet(CR.ComponentName).initEmpty();
        for(pool_components) |component| {
            set.insert(component);
        }
        break :blk set;
    };

    const POOL_MASK = comptime MM.Comptime.createMask(pool_components);

    return struct {
        const Self = @This();
        const pool_name = std.meta.stringToEnum(PR.pool_name, @typeName(@TypeOf(Self))) orelse @compileError("Pool not registred");
        pub const pool_mask = POOL_MASK;
        pub const COMPONENTS = pool_components;

        const MoveDirection = enum {
            adding,
            removing,
        };

        allocator: std.mem.Allocator,
        storage_list: ArrayList(storage_type),
        mask_list: ArrayList(CR.ComponentMask),

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .allocator = allocator,
                .storage_list = ArrayList(storage_type){},
                .mask_list = ArrayList(CR.ComponentMask){},
            };
        }

        fn initStorage(allocator: std.mem.Allocator, mask: CR.ComponentMask) !storage_type {
            var storage: storage_type = undefined;
            inline for(@typeInfo(storage_type).@"struct".fields) |field| {
                if(comptime std.mem.eql(u8, "entities", field.name)) {
                    @field(storage, field.name) = ArrayList(Entity){};
                } else {
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MM.Comptime.componentToBit(component_name);

                    if(MM.maskContains(mask, field_bit)) {
                        const T = CR.getTypeByName(component_name);
                        if(optimize) {
                            @field(storage, field.name) = ArrayList(T){};
                        }
                        else {
                            const array_list_ptr = try allocator.create(ArrayList(T));
                            array_list_ptr.* = ArrayList(T){};
                            @field(storage, field.name) = array_list_ptr;
                        }
                    }
                    else {
                        @field(storage, field.name) = null;
                    }
                }
            }
            return storage;
        }

        fn setStorageComponent(allocator: std.mem.Allocator, storage: *storage_type, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void{
            if(optimize) {
                const field_ptr = &@field(storage.*, @tagName(component));
                var component_array = &field_ptr.*.?;
                try component_array.append(allocator, data);
            } else {
                var component_array_ptr = @field(storage.*, @tagName(component)).?;
                try component_array_ptr.append(allocator, data);
            }
        }

        pub fn addEntity(self: *Self, entity: Entity, comptime component_data: anytype) !struct { index: u32, mask: CR.ComponentMask }{
            const components = comptime blk: {
                const fields = std.meta.fieldNames(@TypeOf(component_data));
                var component_enums: [fields.len]CR.ComponentName = undefined;
                for (fields, 0..) |field, i| {
                    const comp = std.meta.stringToEnum(CR.ComponentName, field) orelse {
                        @compileError("Component not found in registry");
                    };
                    if (!component_set.contains(comp)) {
                        @compileError("Component '" ++ field ++ "' not in this pool");
                    }
                    component_enums[i] = comp;
                }
                break :blk component_enums;
            };

            const mask = comptime MM.Comptime.createMask(&components);
            const storage = try self.getOrCreateStorage(mask);

            try storage.entities.append(self.allocator, entity);

            inline for(components) |component| {
                const T = CR.getTypeByName(component);
                const data = @field(component_data, @tagName(component));

                const typed_data = if (@TypeOf(data) == T) 
                    data
                else blk: {
                    var result: T = undefined;
                    inline for(std.meta.fields(T)) |field| {
                        if(!@hasField(@TypeOf(data), field.name)) {
                            @compileError("Field " ++ field.name ++ " is missing from component " ++ @tagName(component) ++ "!\nMake sure fields of all components are included and spelled properly when using Pool.createEntity()\n");
                        }
                        @field(result, field.name) = @field(data, field.name);
                    }
                    break :blk result;
                };

                _ = try setStorageComponent(self.allocator, storage, component, typed_data);
            }
                return .{
                    .index = @intCast(storage.entities.items.len - 1),
                    .mask = mask,
                };
        }

        // pub fn remove_entity(self: *Self, archetype_index: u32, archetype_mask: CR.ComponentMask) Entity {
        //     var archetype = try self.getOrCreateStorage(archetype_mask);
        //     const swa
        //     inline for(@typeInfo(storage_type).@"struct".fields) |field| {
        //         if(!comptime std.mem.eql(u8, "entities", field.name)) {
        //
        //         }
        //     }
        // }

        fn moveEntity(
            allocator: std.mem.Allocator, 
            new_storage: *storage_type, 
            old_storage: *storage_type, 
            archetype_index: u32, 
            direction: MoveDirection
            ) !struct { added_entity_index: u32, swapped_entity: ?Entity}{
            const entity_index = old_storage.entities.items[archetype_index];
            try new_storage.entities.append(allocator, entity_index);

            const last_index = old_storage.entities.items.len - 1;
            const swapped = archetype_index != last_index;
            const swapped_entity = if(swapped) old_storage.entities.items[last_index] else null;
            const added_entity_index: u32 = @intCast(new_storage.entities.items.len - 1);

            inline for(@typeInfo(storage_type).@"struct".fields) |field| {
                if(!comptime std.mem.eql(u8, "entities", field.name)) {
                    const maybe_new = &@field(new_storage, field.name);
                    const maybe_old = &@field(old_storage, field.name);

                    // Component exists in old but not in new
                    if(maybe_old.* != null and maybe_new.* == null) {
                        if(direction == .adding) return error.ComponentLostDuringAdd; // This shouldn't happen when adding
                        // For .removing, this is expected - just skip copying this component
                    } else if(maybe_new.* != null and maybe_old.* != null) {
                        // Component exists in both - copy it over
                        if(optimize) {
                            var new_array = &maybe_new.*.?;
                            var old_array = &maybe_old.*.?;
                            try new_array.append(allocator, old_array.items[archetype_index]);
                            _ = old_array.swapRemove(archetype_index);
                        } else {
                            var new_array_ptr = maybe_new.*.?;
                            var old_array_ptr = maybe_old.*.?;
                            try new_array_ptr.append(allocator, old_array_ptr.items[archetype_index]);
                            _ = old_array_ptr.swapRemove(archetype_index);
                        }
                    }
                }
                // Component exists in new but not old (.adding case) - will be set separately
            }
            return .{
                .added_entity_index = added_entity_index,
                .swapped_entity = swapped_entity,
            };
        }


        pub fn getOrCreateStorage(self: *Self, mask: CR.ComponentMask) !*storage_type {
            for(self.mask_list.items, 0..) |existing_mask, i| {
                if(existing_mask == mask) {
                    return &self.storage_list.items[i];
                }
            }
            const storage = try initStorage(self.allocator, mask);
            try self.storage_list.append(self.allocator, storage);
            try self.mask_list.append(self.allocator, mask);
            return &self.storage_list.items[self.storage_list.items.len - 1];
        }

        pub fn deinit(self: *Self) void {
            // Clean up all storage
            for (self.storage_list.items) |*storage| {
                inline for (@typeInfo(storage_type).@"struct".fields) |field| {
                    if(comptime std.mem.eql(u8, field.name, "entities")) {
                        @field(storage.*, field.name).deinit(self.allocator);
                    }
                    else if (optimize) {
                        // Optimized: field is ?ArrayList(T)
                        // Get pointer to the field to avoid copying
                        const field_ptr = &@field(storage.*, field.name);
                        if (field_ptr.*) |*array| {
                           array.deinit(self.allocator);
                        }
                    } else {
                        // Non-optimized: field is ?*ArrayList(T)
                        if (@field(storage.*, field.name)) |array_ptr| {
                            array_ptr.deinit(self.allocator);
                            self.allocator.destroy(array_ptr);
                        }
                    }
                }
            }
            self.storage_list.deinit(self.allocator);
            self.mask_list.deinit(self.allocator);
        }

        pub fn addComponent(
            self: *Self,
            entity_mask: CR.ComponentMask,
            entity_pool_mask: CR.ComponentMask,
            archetype_index: u32,
            comptime component: CR.ComponentName,
            data: CR.getTypeByName(component)
        ) !struct { added_entity_index: u32, added_entity_mask: CR.ComponentMask, swapped_entity: ?Entity}{
            comptime {
                var found = false;
                for (pool_components) |comp| {
                    if (comp == component) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    @compileError("Component: " ++ @tagName(component) ++ " does not exist in pool: " ++ @typeName(Self));
                }
            }

            if(entity_pool_mask != pool_mask) {
                std.debug.print("\nEntity assigned pool does not match pool: {s}\n", .{@typeName(Self)});
                return error.EntityPoolMismatch;
            }

            const new_mask = MM.Runtime.addComponent(entity_mask, component);

            // Ensures array lists do not reallocate and invalidate pointers durring function
            try self.mask_list.ensureUnusedCapacity(self.allocator, 2);
            try self.mask_list.ensureUnusedCapacity(self.allocator, 2);

            // Now safely get pointers after all allocations are done
            const old_storage = try self.getOrCreateStorage(entity_mask);
            const new_storage = try self.getOrCreateStorage(new_mask);

            const result = try moveEntity(self.allocator, new_storage, old_storage, archetype_index, .adding);
            _ = try setStorageComponent(self.allocator, new_storage, component, data); // Add the new component data
           return .{
                .added_entity_index = result.added_entity_index,
                .added_entity_mask = new_mask,
                .swapped_entity = result.swapped_entity,
           };
        }


        fn validateComponents(comptime components: []const CR.ComponentName) void {
            for(components) |component|{
                Self.validateComponent(component);
            }
        }

        fn validateComponent(comptime component: CR.ComponentName) void {
            if(!component_set.contains(component)) {
                @compileError("Component '" ++ @tagName(component) ++ "'is not avaiable in this Archetype Pool.\nEither add component to pool, or remove component from entity.");
            }
        }
    };
}

//Later planning on building an API for dev to interact with pools in more intuitive and convient way where entity's are managed.  ArchetypePools are considered "backend"

// test "ArchetypePool - init and deinit" {
//     const allocator = std.testing.allocator;
//     const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);
//     var entity_manager = try EM.EntityManager.init(allocator);
//     defer entity_manager.deinit();
//
//     var pool = try Pool.init(allocator, entity_manager);
//     defer pool.deinit();
//
//     // Pool should start empty
//     try std.testing.expectEqual(0, pool.storage_list.items.len);
//     try std.testing.expectEqual(0, pool.mask_list.items.len);
// }
//
// test "ArchetypePool - create entity with components" {
//     const allocator = std.testing.allocator;
//     var entity_manager = try EM.EntityManager.init(allocator);
//     defer entity_manager.deinit();
//     const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);
//
//     var pool = try Pool.init(allocator, entity_manager);
//     defer pool.deinit();
//
//     const Position = CR.getTypeByName(.Position);
//     const Velocity = CR.getTypeByName(.Velocity);
//
//     // Create entity with both components
//     _ = try pool.addEntity(5, .{
//         .Position = Position{ .x = 10.0, .y = 20.0 },
//         .Velocity = Velocity{ .dx = 1.0, .dy = 2.0 },
//     });
//
//     // Should have created one storage
//     try std.testing.expectEqual(1, pool.storage_list.items.len);
//     try std.testing.expectEqual(1, pool.mask_list.items.len);
//
//     // Create another entity with same components - should reuse storage
//     _ = try pool.addEntity(5, .{
//         .Position = Position{ .x = 40.0, .y = 50.0 },
//         .Velocity = Velocity{ .dx = 4.0, .dy = 5.0 },
//     });
//
//     // Should still have one storage (reused)
//     try std.testing.expectEqual(1, pool.storage_list.items.len);
//     try std.testing.expectEqual(1, pool.mask_list.items.len);
// }
//
// test "ArchetypePool - create entity with partial components" {
//     const allocator = std.testing.allocator;
//     var entity_manager = try EM.EntityManager.init(allocator);
//     defer entity_manager.deinit();
//     const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);
//
//     var pool = try Pool.init(allocator, entity_manager);
//     defer pool.deinit();
//
//     const Position = CR.getTypeByName(.Position);
//
//     // Create entity with only Position
//     _ = try pool.addEntity(5, .{
//         .Position = Position{ .x = 10.0, .y = 20.0 },
//     });
//
//     // Should have one storage
//     try std.testing.expectEqual(1, pool.storage_list.items.len);
//
//     // Now create entity with both components
//     const Velocity = CR.getTypeByName(.Velocity);
//     _ = try pool.addEntity(5, .{
//         .Position = Position{ .x = 40.0, .y = 50.0 },
//         .Velocity = Velocity{ .dx = 1.0, .dy = 2.0 },
//     });
//
//     // Should have two different storages (different masks)
//     try std.testing.expectEqual(2, pool.storage_list.items.len);
//     try std.testing.expectEqual(2, pool.mask_list.items.len);
// }
//
// test "ArchetypePool - getOrCreateStorage with same mask" {
//     const allocator = std.testing.allocator;
//     var entity_manager = try EM.EntityManager.init(allocator);
//     defer entity_manager.deinit();
//     const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);
//
//     var pool = try Pool.init(allocator, entity_manager);
//     defer pool.deinit();
//
//     const mask = MM.Comptime.createMask(&[_]CR.ComponentName{.Position, .Velocity});
//
//     // Get storage for first time
//     const storage1 = try pool.getOrCreateStorage(mask);
//     try std.testing.expectEqual(1, pool.storage_list.items.len);
//
//     // Get storage again with same mask - should return existing
//     const storage2 = try pool.getOrCreateStorage(mask);
//     try std.testing.expectEqual(1, pool.storage_list.items.len);
//
//     // Should be the same storage
//     try std.testing.expectEqual(storage1, storage2);
// }
//
// test "ArchetypePool - non-optimized variant" {
//     const allocator = std.testing.allocator;
//     var entity_manager = try EM.EntityManager.init(allocator);
//     defer entity_manager.deinit();
//     const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);
//
//     var pool = try Pool.init(allocator, entity_manager);
//     defer pool.deinit();
//
//     const Position = CR.getTypeByName(.Position);
//
//     // Create entity
//     _ = try pool.addEntity(5, .{
//         .Position = Position{ .x = 10.0, .y = 20.0 },
//     });
//
//     try std.testing.expectEqual(1, pool.storage_list.items.len);
// }
//
// test "ArchetypePool - addComponent creates new storage" {
//     const allocator = std.testing.allocator;
//     var entity_manager = try EM.EntityManager.init(allocator);
//     defer entity_manager.deinit();
//     const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);
//
//     var pool = try Pool.init(allocator, entity_manager);
//     defer pool.deinit();
//
//     const Position = CR.getTypeByName(.Position);
//     const Velocity = CR.getTypeByName(.Velocity);
//
//     // Create entity with only Position
//     const indx = try pool.addEntity(5, .{
//         .Position = Position{ .x = 10.0, .y = 20.0 },
//     });
//
//     // Should have one storage (Position only)
//     try std.testing.expectEqual(1, pool.storage_list.items.len);
//     const initial_mask = pool.mask_list.items[0];
//
//     // Add Velocity component to entity at index 0
//     _ = try pool.addComponent(
//         initial_mask,
//         indx, // entity_index
//         .Velocity,
//         Velocity{ .dx = 1.0, .dy = 2.0 }
//     );
//
//     // Should now have two storages (Position-only and Position+Velocity)
//     try std.testing.expectEqual(2, pool.storage_list.items.len);
//     try std.testing.expectEqual(2, pool.mask_list.items.len);
// }
//
// test "ArchetypePool - addComponent moves entity data" {
//     const allocator = std.testing.allocator;
//     var entity_manager = try EM.EntityManager.init(allocator);
//     defer entity_manager.deinit();
//     const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);
//
//     var pool = try Pool.init(allocator, entity_manager);
//     defer pool.deinit();
//
//     const Position = CR.getTypeByName(.Position);
//     const Velocity = CR.getTypeByName(.Velocity);
//
//     // Create entity with Position
//     _ = try pool.addEntity(5, .{
//         .Position = Position{ .x = 100.0, .y = 200.0 },
//     });
//
//     const pos_only_mask = pool.mask_list.items[0];
//
//     // Verify Position data is in storage
//     {
//         const pos_only_storage = &pool.storage_list.items[0];
//         const pos_array = @field(pos_only_storage, "Position").?;
//         try std.testing.expectEqual(1, pos_array.items.len);
//         try std.testing.expectEqual(100.0, pos_array.items[0].x);
//         try std.testing.expectEqual(200.0, pos_array.items[0].y);
//     }
//
//     // Add Velocity component
//     _ = try pool.addComponent(
//         pos_only_mask,
//         0,
//         .Velocity,
//         Velocity{ .dx = 5.0, .dy = 10.0 }
//     );
//
//     // Old storage should be empty (entity moved out)
//     // Re-fetch pointer after addComponent since storage_list may have reallocated
//     const pos_only_storage = &pool.storage_list.items[0];
//     const old_pos_array = @field(pos_only_storage, "Position").?;
//     try std.testing.expectEqual(0, old_pos_array.items.len);
//
//     // New storage should have both components
//     const new_storage = &pool.storage_list.items[1];
//     const new_pos_array = @field(new_storage, "Position").?;
//     const new_vel_array = @field(new_storage, "Velocity").?;
//
//     try std.testing.expectEqual(1, new_pos_array.items.len);
//     try std.testing.expectEqual(1, new_vel_array.items.len);
//
//     // Verify Position data was moved correctly
//     try std.testing.expectEqual(100.0, new_pos_array.items[0].x);
//     try std.testing.expectEqual(200.0, new_pos_array.items[0].y);
//
//     // Verify Velocity data was added
//     try std.testing.expectEqual(5.0, new_vel_array.items[0].dx);
//     try std.testing.expectEqual(10.0, new_vel_array.items[0].dy);
// }
