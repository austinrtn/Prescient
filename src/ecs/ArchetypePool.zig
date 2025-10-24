const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const ArrayList = std.ArrayList;

fn ComponentArrayStorage(comptime pool_components: []const CR.ComponentName, comptime optimize: bool) type {
    var fields: [pool_components.len]std.builtin.Type.StructField = undefined;
    
    inline for(pool_components, 0..) |component, i| {
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

    const pool_mask = MM.Comptime.createMask(pool_components);

    return struct {
        const Self = @This();
        const signature = pool_mask;

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

        pub fn initStorage(allocator: std.mem.Allocator, mask: CR.ComponentMask) !storage_type {
            var storage: storage_type = undefined;
            inline for(@typeInfo(storage_type).@"struct".fields) |field| {
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
            return storage;
        }

        fn setStorageComponent(allocator: std.mem.Allocator, storage: *storage_type, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void {
            if(optimize) {
                var component_array = @field(storage, @tagName(component)).?;
                try component_array.append(allocator, data);
            } else {
                var component_array_ptr = @field(storage, @tagName(component)).?;
                try component_array_ptr.append(allocator, data);
            }
        }

        fn moveEntity(allocator: std.mem.Allocator, new_storage: *storage_type, old_storage: *storage_type, entity: usize, direction: MoveDirection) !void {
            inline for(@typeInfo(storage_type).@"struct".fields) |field| {
                const maybe_new = @field(new_storage, field.name);
                const maybe_old = @field(old_storage, field.name);

                // Component exists in old but not in new
                if(maybe_old != null and maybe_new == null) {
                    if(direction == .adding) return error.ComponentLostDuringAdd; // This shouldn't happen when adding
                    // For .removing, this is expected - just skip copying this component
                } else if(maybe_new != null and maybe_old != null) {
                    // Component exists in both - copy it over
                    if(optimize) {
                        var new_array = maybe_new.?;
                        var old_array = maybe_old.?;
                        try new_array.append(allocator, old_array.items[entity]);
                        _ = old_array.swapRemove(entity);
                    } else {
                        var new_array_ptr = maybe_new.?;
                        var old_array_ptr = maybe_old.?;
                        try new_array_ptr.append(allocator, old_array_ptr.items[entity]);
                        _ = old_array_ptr.swapRemove(entity);
                    }
                }
                // Component exists in new but not old (.adding case) - will be set separately
            }
        }

        pub fn createEntity(self: *Self, comptime component_data: anytype) !void {
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

            inline for(components) |component| {
                const T = CR.getTypeByName(component);
                const data = @field(component_data, @tagName(component));
                const typed_data = @as(T, data);
                try setStorageComponent(self.allocator, storage, component, typed_data);
            }
        }

        pub fn getOrCreateStorage(self: *Self, mask: CR.ComponentMask) !*storage_type {
            for(self.mask_list.items, 0..) |existing_mask, i| {
                if(existing_mask == mask) return &self.storage_list.items[i];
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
                    var maybe_array = @field(storage, field.name);
                    if (maybe_array) |*array| {
                        if (optimize) {
                            // Optimized: array is inline, just deinit
                            array.*.deinit(self.allocator);
                        } else {
                            // Non-optimized: array is a pointer, deinit then destroy
                            array.*.deinit(self.allocator);
                            self.allocator.destroy(array.*);
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
            entity_index: usize,
            comptime component: CR.ComponentName,
            data: CR.getTypeByName(component)
        ) !void {
            const new_mask = MM.Runtime.addComponent(entity_mask, component);
            const old_storage = try self.getOrCreateStorage(entity_mask);
            const new_storage = try self.getOrCreateStorage(new_mask);

            try moveEntity(self.allocator, new_storage, old_storage, entity_index, .adding);

            // Add the new component data
            try setStorageComponent(self.allocator, new_storage, component, data);
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

test "ArchetypePool - init and deinit" {
    const allocator = std.testing.allocator;
    const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    // Pool should start empty
    try std.testing.expectEqual(0, pool.storage_list.items.len);
    try std.testing.expectEqual(0, pool.mask_list.items.len);
}

test "ArchetypePool - create entity with components" {
    const allocator = std.testing.allocator;
    const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    const Position = CR.getTypeByName(.Position);
    const Velocity = CR.getTypeByName(.Velocity);

    // Create entity with both components
    try pool.createEntity(.{
        .Position = Position{ .x = 10.0, .y = 20.0 },
        .Velocity = Velocity{ .dx = 1.0, .dy = 2.0 },
    });

    // Should have created one storage
    try std.testing.expectEqual(1, pool.storage_list.items.len);
    try std.testing.expectEqual(1, pool.mask_list.items.len);

    // Create another entity with same components - should reuse storage
    try pool.createEntity(.{
        .Position = Position{ .x = 40.0, .y = 50.0 },
        .Velocity = Velocity{ .dx = 4.0, .dy = 5.0 },
    });

    // Should still have one storage (reused)
    try std.testing.expectEqual(1, pool.storage_list.items.len);
    try std.testing.expectEqual(1, pool.mask_list.items.len);
}

test "ArchetypePool - create entity with partial components" {
    const allocator = std.testing.allocator;
    const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    const Position = CR.getTypeByName(.Position);

    // Create entity with only Position
    try pool.createEntity(.{
        .Position = Position{ .x = 10.0, .y = 20.0 },
    });

    // Should have one storage
    try std.testing.expectEqual(1, pool.storage_list.items.len);

    // Now create entity with both components
    const Velocity = CR.getTypeByName(.Velocity);
    try pool.createEntity(.{
        .Position = Position{ .x = 40.0, .y = 50.0 },
        .Velocity = Velocity{ .dx = 1.0, .dy = 2.0 },
    });

    // Should have two different storages (different masks)
    try std.testing.expectEqual(2, pool.storage_list.items.len);
    try std.testing.expectEqual(2, pool.mask_list.items.len);
}

test "ArchetypePool - getOrCreateStorage with same mask" {
    const allocator = std.testing.allocator;
    const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    const mask = MM.Comptime.createMask(&[_]CR.ComponentName{.Position, .Velocity});

    // Get storage for first time
    const storage1 = try pool.getOrCreateStorage(mask);
    try std.testing.expectEqual(1, pool.storage_list.items.len);

    // Get storage again with same mask - should return existing
    const storage2 = try pool.getOrCreateStorage(mask);
    try std.testing.expectEqual(1, pool.storage_list.items.len);

    // Should be the same storage
    try std.testing.expectEqual(storage1, storage2);
}

test "ArchetypePool - non-optimized variant" {
    const allocator = std.testing.allocator;
    const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, false);

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    const Position = CR.getTypeByName(.Position);

    // Create entity
    try pool.createEntity(.{
        .Position = Position{ .x = 10.0, .y = 20.0 },
    });

    try std.testing.expectEqual(1, pool.storage_list.items.len);
}

test "ArchetypePool - addComponent creates new storage" {
    const allocator = std.testing.allocator;
    const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    const Position = CR.getTypeByName(.Position);
    const Velocity = CR.getTypeByName(.Velocity);

    // Create entity with only Position
    try pool.createEntity(.{
        .Position = Position{ .x = 10.0, .y = 20.0 },
    });

    // Should have one storage (Position only)
    try std.testing.expectEqual(1, pool.storage_list.items.len);
    const initial_mask = pool.mask_list.items[0];

    // Add Velocity component to entity at index 0
    try pool.addComponent(
        initial_mask,
        0, // entity_index
        .Velocity,
        Velocity{ .dx = 1.0, .dy = 2.0 }
    );

    // Should now have two storages (Position-only and Position+Velocity)
    try std.testing.expectEqual(2, pool.storage_list.items.len);
    try std.testing.expectEqual(2, pool.mask_list.items.len);
}

test "ArchetypePool - addComponent moves entity data" {
    const allocator = std.testing.allocator;
    const Pool = ArchetypePool(&[_]CR.ComponentName{.Position, .Velocity}, true);

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    const Position = CR.getTypeByName(.Position);
    const Velocity = CR.getTypeByName(.Velocity);

    // Create entity with Position
    try pool.createEntity(.{
        .Position = Position{ .x = 100.0, .y = 200.0 },
    });

    const pos_only_mask = pool.mask_list.items[0];
    const pos_only_storage = &pool.storage_list.items[0];

    // Verify Position data is in storage
    const pos_array = @field(pos_only_storage, "Position").?;
    try std.testing.expectEqual(1, pos_array.items.len);
    try std.testing.expectEqual(100.0, pos_array.items[0].x);
    try std.testing.expectEqual(200.0, pos_array.items[0].y);

    // Add Velocity component
    try pool.addComponent(
        pos_only_mask,
        0,
        .Velocity,
        Velocity{ .dx = 5.0, .dy = 10.0 }
    );

    // Old storage should be empty (entity moved out)
    const old_pos_array = @field(pos_only_storage, "Position").?;
    try std.testing.expectEqual(0, old_pos_array.items.len);

    // New storage should have both components
    const new_storage = &pool.storage_list.items[1];
    const new_pos_array = @field(new_storage, "Position").?;
    const new_vel_array = @field(new_storage, "Velocity").?;

    try std.testing.expectEqual(1, new_pos_array.items.len);
    try std.testing.expectEqual(1, new_vel_array.items.len);

    // Verify Position data was moved correctly
    try std.testing.expectEqual(100.0, new_pos_array.items[0].x);
    try std.testing.expectEqual(200.0, new_pos_array.items[0].y);

    // Verify Velocity data was added
    try std.testing.expectEqual(5.0, new_vel_array.items[0].dx);
    try std.testing.expectEqual(10.0, new_vel_array.items[0].dy);
}
