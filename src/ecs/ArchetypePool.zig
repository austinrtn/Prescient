const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PR = @import("PoolRegistry.zig");

const ArrayList = std.ArrayList;
const Entity = EM.Entity;

fn ComponentArrayStorage(comptime pool_components: []const CR.ComponentName) type {
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
        const archetype_type = ?*ArrayList(T);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = archetype_type,
            .alignment = @alignOf(archetype_type),
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

pub fn ArchetypePool(comptime req: []const CR.ComponentName, comptime opt: []const CR.ComponentName) type {
    const pool_components = req ++ opt;
    const archetype_type = ComponentArrayStorage(pool_components);
    const POOL_MASK = comptime MM.Comptime.createMask(pool_components);

    return struct {
        const Self = @This();
        const pool_name = std.meta.stringToEnum(PR.pool_name, @typeName(@TypeOf(Self))) orelse @compileError("Pool not registred");

        pub const pool_mask = POOL_MASK;
        pub const REQ_MASK = MM.Comptime.createMask(req);
        pub const COMPONENTS = pool_components;

        const MoveDirection = enum {
            adding,
            removing,
        };
        
        pub var instance: ?*Self = null;
        allocator: std.mem.Allocator,
        archetype_list: ArrayList(archetype_type),
        mask_list: ArrayList(CR.ComponentMask),

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = .{
                .allocator = allocator,
                .archetype_list = ArrayList(archetype_type){},
                .mask_list = ArrayList(CR.ComponentMask){},
            };

            instance = &self; 
            return self;
        }

        fn initArchetype(allocator: std.mem.Allocator, mask: CR.ComponentMask) !archetype_type {
            var archetype: archetype_type = undefined;
            inline for(@typeInfo(archetype_type).@"struct".fields) |field| {
                if(comptime std.mem.eql(u8, "entities", field.name)) {
                    @field(archetype, field.name) = ArrayList(Entity){};
                } else {
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MM.Comptime.componentToBit(component_name);

                    if(MM.maskContains(mask, field_bit)) {
                        const T = CR.getTypeByName(component_name);
                        const array_list_ptr = try allocator.create(ArrayList(T));
                        array_list_ptr.* = ArrayList(T){};
                        @field(archetype, field.name) = array_list_ptr;
                    }
                    else {
                        @field(archetype, field.name) = null;
                    }
                }
            }
            return archetype;
        }

        fn setArchetypeComponent(allocator: std.mem.Allocator, archetype: *archetype_type, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void{
            var component_array_ptr = @field(archetype.*, @tagName(component)).?;
            try component_array_ptr.append(allocator, data);
        }

        fn getArchetype(self: *Self, mask: CR.ComponentMask) ?*archetype_type {
            for(self.mask_list.items, 0..) |existing_mask, i| {
                if(existing_mask == mask) {
                    return &self.archetype_list.items[i];
                }
            }
            return null;
        }

        fn getOrCreateArchetype(self: *Self, mask: CR.ComponentMask) !*archetype_type {
            if(self.getArchetype(mask)) |archetype| {
                return archetype;
            }
            else {
                const archetype = try initArchetype(self.allocator, mask);
                try self.archetype_list.append(self.allocator, archetype);
                try self.mask_list.append(self.allocator, mask);
                return &self.archetype_list.items[self.archetype_list.items.len - 1];
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
                    validateComponentInPool(comp);
                    component_enums[i] = comp;
                }
                break :blk component_enums;
            };

            comptime {
                if(req.len > 0) validateAllRequiredComponents(&components);
            }

            const mask = comptime MM.Comptime.createMask(&components);
            const archetype = try self.getOrCreateArchetype(mask);

            try archetype.entities.append(self.allocator, entity);

            inline for(components) |component| {
                const T = CR.getTypeByName(component);
                const data = @field(component_data, @tagName(component));

                const typed_data = if (@TypeOf(data) == T)
                    data
                else blk: {
                    var result: T = undefined;
                    inline for(std.meta.fields(T)) |field| {
                        if(!@hasField(@TypeOf(data), field.name)) {
                            @compileError("Field " ++ field.name ++ " is missing from component "
                                ++ @tagName(component) ++ "!\nMake sure fields of all components are included and spelled properly when using Pool.createEntity()\n");
                        }
                        @field(result, field.name) = @field(data, field.name);
                    }
                    break :blk result;
                };

                _ = try setArchetypeComponent(self.allocator, archetype, component, typed_data);
            }
                return .{
                    .index = @intCast(archetype.entities.items.len - 1),
                    .mask = mask,
                };
        }

        pub fn remove_entity(self: *Self, archetype_index: u32, entity_mask: CR.ComponentMask, entity_pool_mask: CR.ComponentMask) !Entity {
            try validateEntityInPool(entity_pool_mask);
            var archetype = self.getArchetype(entity_mask) orelse return error.ArchetypeDoesNotExist;

            const swapped_entity = archetype.entities.items[archetype.entities.items.len - 1];
            _ = archetype.entities.swapRemove(archetype_index);

            inline for(@typeInfo(archetype_type).@"struct".fields) |field| {
                if(!comptime std.mem.eql(u8, "entities", field.name)) {
                    // Get component bit at comptime
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MM.Comptime.componentToBit(component_name);

                    // Only process if this component exists in the entity's mask
                    if (MM.maskContains(entity_mask, field_bit)) {
                        const component_array = &@field(archetype, field.name);
                        if(component_array.* != null)  {
                            var comp_array = component_array.*.?;
                            _ = comp_array.swapRemove(archetype_index);
                        }
                    }
                }
            }
            return swapped_entity;
        }

        pub fn getComponent(
            self: *Self, 
            archetype_index: u32, 
            entity_mask: CR.ComponentMask, 
            entity_pool_mask: CR.ComponentMask, 
            comptime component: CR.ComponentName) !*CR.getTypeByName(component) {

            validateComponentInPool(component);
            try validateEntityInPool(entity_pool_mask);
            try validateComponentInArchetype(entity_mask, component);

            const archetype = self.getArchetype(entity_mask) orelse return error.ArchetypeDoesNotExist;

            const component_array = @field(archetype, @tagName(component));
            return &component_array.?.items[archetype_index];
        }

        pub fn addComponent(
            self: *Self,
            entity_mask: CR.ComponentMask,
            entity_pool_mask: CR.ComponentMask,
            archetype_index: u32,
            comptime component: CR.ComponentName,
            data: CR.getTypeByName(component)
        ) !struct { added_entity_index: u32, added_entity_mask: CR.ComponentMask, swapped_entity: ?Entity}{
            // Compile-time validation: ensure component exists in this pool
            validateComponentInPool(component);

            // Runtime validation: ensure entity belongs to this pool
            try validateEntityInPool(entity_pool_mask);

            const new_mask = MM.Runtime.addComponent(entity_mask, component);

            // Ensures array lists do not reallocate and invalidate pointers durring function
            try self.mask_list.ensureUnusedCapacity(self.allocator, 2);
            try self.archetype_list.ensureUnusedCapacity(self.allocator, 2);

            // Now safely get pointers after all allocations are done
            const src_archetype = try self.getOrCreateArchetype(entity_mask);
            const dest_archetype = try self.getOrCreateArchetype(new_mask);

            const result = try moveEntity(self.allocator, dest_archetype, new_mask, src_archetype, entity_mask, archetype_index, .adding);
            try setArchetypeComponent(self.allocator, dest_archetype, component, data); // Add the new component data

            return .{
                .added_entity_index = result.added_entity_index,
                .added_entity_mask = new_mask,
                .swapped_entity = result.swapped_entity,
            };
        }

        pub fn removeComponent(
            self: *Self,
            entity_mask: CR.ComponentMask,
            entity_pool_mask: CR.ComponentMask,
            archetype_index: u32,
            comptime component: CR.ComponentName,
        ) !struct { removed_entity_index: u32, removed_entity_mask: CR.ComponentMask, swapped_entity: ?Entity}{
            validateComponentInPool(component);
            comptime {
                for(req) |req_comp| {
                    if(req_comp == component) {
                        @compileError("You can not remove required component " ++ @tagName(component) ++ " from pool " ++ @typeName(Self));
                    }
                }
            }

            try validateEntityInPool(entity_pool_mask);

            const new_mask = MM.Runtime.removeComponent(entity_mask, component);

            // Ensures array lists do not reallocate and invalidate pointers durring function
            try self.mask_list.ensureUnusedCapacity(self.allocator, 2);
            try self.archetype_list.ensureUnusedCapacity(self.allocator, 2);

            // Now safely get pointers after all allocations are done
            const src_archetype = try self.getOrCreateArchetype(entity_mask);
            const dest_archetype = try self.getOrCreateArchetype(new_mask);

            const result = try moveEntity(self.allocator, dest_archetype, new_mask, src_archetype, entity_mask, archetype_index, .removing);
            return .{
                .removed_entity_index = result.added_entity_index,
                .removed_entity_mask = new_mask,
                .swapped_entity = result.swapped_entity,
            };
        }

        fn moveEntity(
            allocator: std.mem.Allocator,
            dest_archetype: *archetype_type,
            new_mask: CR.ComponentMask,
            src_archetype: *archetype_type,
            old_mask: CR.ComponentMask,
            archetype_index: u32,
            direction: MoveDirection
            ) !struct { added_entity_index: u32, swapped_entity: ?Entity }{
            const entity_index = src_archetype.entities.items[archetype_index];
            try dest_archetype.entities.append(allocator, entity_index);

            const last_index = src_archetype.entities.items.len - 1;
            const swapped = archetype_index != last_index;
            const swapped_entity = if(swapped) src_archetype.entities.items[last_index] else null;
            const added_entity_index: u32 = @intCast(dest_archetype.entities.items.len - 1);

            inline for(@typeInfo(archetype_type).@"struct".fields) |field| {
                if(!comptime std.mem.eql(u8, "entities", field.name)) {
                    // Get component bit at comptime
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MM.Comptime.componentToBit(component_name);

                    // Skip if component doesn't exist in either mask
                    if (MM.maskContains(new_mask, field_bit) or MM.maskContains(old_mask, field_bit)) {
                        const maybe_src = &@field(src_archetype, field.name);
                        const maybe_dest = &@field(dest_archetype, field.name);

                        // Component exists in src but not in dest
                        if(maybe_src.* != null and maybe_dest.* == null) {
                            if(direction == .adding) return error.ComponentLostDuringAdd; // This shouldn't happen when adding
                            // For .removing, this is expected - just skip copying this component
                        } else if(maybe_dest.* != null and maybe_src.* != null) {
                            // Component exists in both - copy it over
                            var dest_array_ptr = maybe_dest.*.?;
                            var src_array_ptr = maybe_src.*.?;
                            try dest_array_ptr.append(allocator, src_array_ptr.items[archetype_index]);
                            _ = src_array_ptr.swapRemove(archetype_index);
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

        pub fn deinit(self: *Self) void {
            // Clean up all archetypes
            for (self.archetype_list.items) |*archetype| {
                inline for (@typeInfo(archetype_type).@"struct".fields) |field| {
                    if(comptime std.mem.eql(u8, field.name, "entities")) {
                        @field(archetype.*, field.name).deinit(self.allocator);
                    } else {
                        // Field is ?*ArrayList(T)
                        if (@field(archetype.*, field.name)) |array_ptr| {
                            array_ptr.deinit(self.allocator);
                            self.allocator.destroy(array_ptr);
                        }
                    }
                }
            }
            self.archetype_list.deinit(self.allocator);
            self.mask_list.deinit(self.allocator);
        }

        fn checkIfEntInPool(entity_pool_mask: CR.ComponentMask) bool {
            return entity_pool_mask == pool_mask;
        }

        fn validateAllRequiredComponents(comptime components: []const CR.ComponentName) void {
            inline for (req) |required_comp| {
                var found = false;
                inline for (components) |provided_comp| {
                    if (required_comp == provided_comp) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    @compileError("Required component '" ++ @tagName(required_comp) ++
                        "' is missing when creating entity in pool " ++ @typeName(Self));
                }
            }
        }

        fn validateComponentInArchetype(archetype_mask: CR.ComponentMask, component: CR.ComponentName) !void {
            if(!MM.maskContains(archetype_mask, MM.Runtime.componentToBit(component))) {
                std.debug.print("\nEntity does not have component: {s}\n", .{@tagName(component)});
                return error.ComponentNotInArchetype;
            }
        }

        fn validateEntityInPool(entity_pool_mask: CR.ComponentMask) !void {
            if(!checkIfEntInPool(entity_pool_mask)){
                std.debug.print("\nEntity assigned pool does not match pool: {s}\n", .{@typeName(Self)});
                return error.EntityPoolMismatch;
            }
        }

        fn validateComponentInPool(comptime component: CR.ComponentName) void {
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
