const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PC = @import("PoolConfig.zig");
const PoolConfig = PC.PoolConfig;
const PoolName = PC.PoolName;
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const Entity = EM.Entity;
const EB = @import("EntityBuilder.zig");
const EntityBuilderType = EB.EntityBuilderType;
const MQ = @import("MigrationQueue.zig");
const MoveDirection = MQ.MoveDirection;
const MigrationQueueType = MQ.MigrationQueueType;
const MigrationEntryType = MQ.MigrationEntryType;
const PoolInterfaceType = @import("PoolInterface.zig").PoolInterfaceType;
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;

const BitmaskMap = struct { bitmask_index: u32, in_list_index: u32};

fn StorageType(comptime components: []const CR.ComponentName) type {
    const field_count = components.len + 2;
    var fields:[field_count] std.builtin.Type.StructField = undefined;
    
    //~Field: entities: AL(Entity)
    fields[0] = .{
        .name = "entities",
        .type = ArrayList(?Entity),
        .alignment = @alignOf(ArrayList(?Entity)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:bitmask_index: u32
    fields[1] = .{
        .name = "bitmask_map",
        .type = ArrayList(?BitmaskMap),
        .alignment = @alignOf(ArrayList(?BitmaskMap)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:component: AL(?Component)
    for(components, (field_count - components.len)..) |component, i| {
        const name = @tagName(component);
        const comp_type = CR.getTypeByName(component);
        const T = ArrayList(?comp_type);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
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
pub fn SparseSetPoolType(comptime config: PoolConfig) type {
    const req = if(config.req) |req_comps| req_comps else &.{};
    const components_list = if(config.components) |comp| comp else &.{};

    const pool_components = comptime blk: {
        if(req.len == 0 and components_list.len == 0) {
            @compileError("\nPool must contain at least one component!\n");
        }

        if(req.len == 0 and components_list.len > 0) {
            break :blk components_list;
        }

        else if(req.len > 0 and components_list.len == 0) {
            break :blk req;
        }

        else {
            break :blk req ++ components_list;
        }
    };

    const POOL_MASK = comptime MaskManager.Comptime.createMask(pool_components);
    const MigrationQueue = MQ.MigrationQueueType(pool_components);

    const Storage = StorageType(pool_components);
    return struct {
        const Self = @This();
        pub const NAME = config.name;
        pub const pool_mask = POOL_MASK;
        pub const storage_strategy: StorageStrategy = .SPARSE;
        pub const REQ_MASK = MaskManager.Comptime.createMask(req);
        pub const COMPONENTS = pool_components;
        pub const REQ_COMPONENTS = req;
        pub const COMPONENTS_LIST = components_list;
        pub const Builder = EntityBuilderType(req, components_list);

        allocator: Allocator,
        storage: Storage,
        masks: ArrayList(struct {
            mask: MaskManager.Mask,
            storage_indexes: ArrayList(u32),
        }),
        empty_indexes: ArrayList(usize),
        migration_queue: MigrationQueue,


        pub fn init(allocator: Allocator) Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.masks = .{};
            self.empty_indexes = .{};
            self.migration_queue = MigrationQueue.init(allocator);

            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name) = .{};
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).deinit(self.allocator);
            }
            for (self.masks.items) |*mask_entry| {
                mask_entry.storage_indexes.deinit(self.allocator);
            }
            self.masks.deinit(self.allocator);
            self.empty_indexes.deinit(self.allocator);
            self.migration_queue.deinit();
        }

        pub fn getInterface(self: *Self, entity_manager: *EM.EntityManager) PoolInterfaceType(NAME) {
            return PoolInterfaceType(NAME).init(self, entity_manager);
        }

        pub fn addEntity(self: *Self, entity: EM.Entity, comptime component_data: Builder) !struct { storage_index: u32, archetype_index: u32 } {
            const components = comptime EB.getComponentsFromData(pool_components, Builder, component_data);
            const bitmask = MaskManager.Comptime.createMask(components);

            const storage_index: u32 = @intCast(self.empty_indexes.pop() orelse blk: {
                inline for(std.meta.fields(Storage)) |field| {
                    try @field(self.storage, field.name).append(self.allocator, null);
                }
                break :blk self.storage.entities.items.len - 1;
            });

            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[storage_index] = null;
            }

            inline for(components) |component| {
                const T = CR.getTypeByName(component);
                const field_value = @field(component_data, @tagName(component));

                // Unwrap optional if needed
                const data = comptime blk: {
                    const field_info = for (std.meta.fields(Builder)) |f| {
                        if (std.mem.eql(u8, f.name, @tagName(component))) break f;
                    } else unreachable;

                    const is_optional = @typeInfo(field_info.type) == .optional;
                    if (is_optional) {
                        break :blk field_value.?; // Unwrap the optional
                    } else {
                        break :blk field_value; // Already non-optional
                    }
                };

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

                @field(self.storage, @tagName(component)).items[storage_index] = typed_data;
            }

            self.storage.entities.items[storage_index] = entity;
            const new_bitmask_map = try self.getOrCreateBitmaskMap(bitmask);
            self.storage.bitmask_map.items[storage_index] = new_bitmask_map;
            try self.masks.items[@intCast(new_bitmask_map.bitmask_index)].storage_indexes.append(self.allocator, storage_index);

            return .{
                .storage_index = storage_index,
                .archetype_index = new_bitmask_map.bitmask_index,
            };
        }

        pub fn removeEntity(self: *Self, storage_index: u32, pool_name: PoolName) !void {
            try validateEntityInPool(pool_name);

            const bitmask_map = self.getBitmaskMap(storage_index);
            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[storage_index] = null;
            }

            self.removeFromMaskList(bitmask_map);
            try self.empty_indexes.append(self.allocator, storage_index);
        }

        pub fn addOrRemoveComponent(
            self: *Self,
            entity: Entity,
            _: u32, // mask_list_index - unused for SparseSetPool, kept for API uniformity
            pool_name: PoolName,
            storage_index: u32,
            is_migrating: bool,
            comptime direction: MoveDirection,
            comptime component: CR.ComponentName,
            data: ?CR.getTypeByName(component)
        ) !void {
            // Compile-time validation: ensure component exists in this pool
            validateComponentInPool(component);

            // Runtime validation: ensure entity belongs to this pool
            try validateEntityInPool(pool_name);

            // Check to make sure user is not removing a required component
            comptime {
                if (direction == .removing) {
                    for (req) |req_comp| {
                        if (req_comp == component) {
                            @compileError("You can not remove required component "
                                ++ @tagName(component) ++ " from pool " ++ @typeName(Self));
                        }
                    }
                }
            }

            // Make sure component has non-null data when adding component
            // Should be null when removing component
            if (direction == .adding and data == null) {
                std.debug.print("\ncomponent data cannot be null when adding a component!\n", .{});
                return error.NullComponentData;
            }

            const bitmask_map = self.getBitmaskMap(storage_index);
            const entity_mask = self.getBitmask(bitmask_map.bitmask_index);
            const component_bit = MaskManager.Comptime.componentToBit(component);

            if (direction == .adding) {
                if (MaskManager.maskContains(entity_mask, component_bit)) {
                    return error.AddingExistingComponent;
                }
                const new_mask = MaskManager.Runtime.addComponent(entity_mask, component);

                const component_data = @unionInit(
                    MigrationQueue.Entry.ComponentDataUnion,
                    @tagName(component),
                    data
                );

                try self.migration_queue.addMigration(
                    entity,
                    storage_index,
                    entity_mask,
                    new_mask,
                    .adding,
                    component_bit,
                    component_data,
                    is_migrating,
                );
            } else if (direction == .removing) {
                if (!MaskManager.maskContains(entity_mask, component_bit)) {
                    return error.RemovingNonexistingComponent;
                }
                const new_mask = MaskManager.Runtime.removeComponent(entity_mask, component);

                const component_data = @unionInit(
                    MigrationQueue.Entry.ComponentDataUnion,
                    @tagName(component),
                    null
                );

                try self.migration_queue.addMigration(
                    entity,
                    storage_index,
                    entity_mask,
                    new_mask,
                    .removing,
                    component_bit,
                    component_data,
                    is_migrating,
                );
            }
        }

        pub fn addComponent(self: *Self, storage_index: u32, comptime component:CR.ComponentName, value: CR.getTypeByName(component)) !void {
            const bitmask_map = self.getBitmaskMap(storage_index);
            const old_bitmask = self.getBitmask(bitmask_map.bitmask_index);

            const new_bitmask = MaskManager.Comptime.addComponent(old_bitmask, component);
            const comp_storage = &@field(self.storage, @tagName(component)).items[storage_index];
            if(comp_storage.* != null) return error.EntityAlreadyHasComponent;

            self.removeFromMaskList(bitmask_map); 
           
            const new_bitmask_map = try self.getOrCreateBitmaskMap(new_bitmask);
            try self.masks.items[new_bitmask_map.bitmask_index].storage_indexes.append(self.allocator, storage_index);
            self.storage.bitmask_map.items[storage_index] = new_bitmask_map;

            comp_storage.* = value; 
        }

        pub fn removeComponent(self: *Self, storage_index: u32, comptime component:CR.ComponentName) !void {
            const bitmask_map = self.getBitmaskMap(storage_index);
            const bitmask = self.getBitmask(bitmask_map.bitmask_index);

            const new_bitmask = MaskManager.Comptime.removeComponent(bitmask, component);
            const comp_storage = &@field(self.storage, @tagName(component)).items[storage_index];

            if(comp_storage.* == null) return error.EntityDoesNotHaveComponent;
            self.removeFromMaskList(bitmask_map);

            const new_bitmask_mask = try self.getOrCreateBitmaskMap(new_bitmask);
            try self.masks.items[new_bitmask_mask.bitmask_index].storage_indexes.append(self.allocator, storage_index);
            self.storage.bitmask_map.items[storage_index] = new_bitmask_mask;

            comp_storage.* = null;
        }

        /// Migration result for SparseSetPool - no swapped_entity since storage_index is stable
        pub const SparseMigrationResult = struct {
            entity: Entity,
            storage_index: u32,
            bitmask_index: u32,
        };

        pub fn flushMigrationQueue(self: *Self) ![]SparseMigrationResult {
            if (self.migration_queue.count() == 0) return &.{};

            var results = ArrayList(SparseMigrationResult){};
            try results.ensureTotalCapacity(self.allocator, self.migration_queue.count());

            var iter = self.migration_queue.iterator();
            while (iter.next()) |kv| {
                const entity = kv.key_ptr.*;
                var entries = kv.value_ptr.*;

                if (entries.items.len == 0) continue;

                const first_entry = entries.items[0];
                const storage_index = first_entry.storage_index;

                // Step 1: Resolve - compute final mask from all entries
                var final_mask = first_entry.old_mask;
                for (entries.items) |entry| {
                    if (entry.direction == .adding) {
                        final_mask |= entry.component_mask;
                    } else {
                        final_mask &= ~entry.component_mask;
                    }
                }

                // Step 2: Update mask group membership
                const old_bitmask_map = self.getBitmaskMap(storage_index);
                self.removeFromMaskList(old_bitmask_map);

                const new_bitmask_map = try self.getOrCreateBitmaskMap(final_mask);
                try self.masks.items[new_bitmask_map.bitmask_index].storage_indexes.append(self.allocator, storage_index);
                self.storage.bitmask_map.items[storage_index] = new_bitmask_map;

                // Step 3: Apply component data changes in-place
                for (entries.items) |entry| {
                    switch (entry.component_data) {
                        inline else => |data, tag| {
                            const comp_storage = &@field(self.storage, @tagName(tag)).items[storage_index];
                            if (entry.direction == .adding) {
                                comp_storage.* = data;
                            } else {
                                comp_storage.* = null;
                            }
                        }
                    }
                }

                try results.append(self.allocator, .{
                    .entity = entity,
                    .storage_index = storage_index,
                    .bitmask_index = new_bitmask_map.bitmask_index,
                });

                // Clean up entry list
                entries.deinit(self.allocator);
            }

            self.migration_queue.clear();
            return try results.toOwnedSlice(self.allocator);
        }

        pub fn getComponent(
            self: *Self,
            _: u32, // mask_list_index - unused for SparseSetPool, kept for API uniformity
            storage_index: u32,
            pool_name: PoolName,
            comptime component: CR.ComponentName
        ) !*CR.getTypeByName(component) {
            validateComponentInPool(component);
            try validateEntityInPool(pool_name);

            const result = &@field(self.storage, @tagName(component)).items[@intCast(storage_index)];
            if(result.*) |*comp_data| {
                return comp_data;
            } else {
                return error.EntityDoesNotHaveComponent;
            }
        }

        fn getBitmaskMap(self: *Self, storage_index: u32) BitmaskMap {
            const index: usize = @intCast(storage_index);
            return self.storage.bitmask_map.items[index].?;
        }

        fn getBitmask(self: *Self, bitmask_index: u32) MaskManager.Mask {
            const index: usize = @intCast(bitmask_index);
            return self.masks.items[index].mask;
        }

        fn removeFromMaskList(self: *Self, bitmask_map: BitmaskMap) void {
            const storage_indexes = &self.masks.items[bitmask_map.bitmask_index].storage_indexes;

            // swapRemove removes the element and moves the last element to this position
            _ = storage_indexes.swapRemove(bitmask_map.in_list_index);

            // If we didn't remove the last element, update the bitmask_map for the swapped entity
            if (bitmask_map.in_list_index < storage_indexes.items.len) {
                const swapped_storage_index = storage_indexes.items[bitmask_map.in_list_index];
                self.storage.bitmask_map.items[swapped_storage_index].?.in_list_index = bitmask_map.in_list_index;
            }
        }

        fn getOrCreateBitmaskMap(self: *Self, bitmask: MaskManager.Mask) !BitmaskMap { //getOrCreateBitmaskMap
            for (self.masks.items, 0..) |mask_entry, i| {
                if (mask_entry.mask == bitmask) {
                    const bitmask_index: usize = @intCast(i);
                    const storage_indexes = self.masks.items[i].storage_indexes;
                    const in_list_index = storage_indexes.items.len;

                    return . {
                        .bitmask_index = @intCast(bitmask_index),
                        .in_list_index = @intCast(in_list_index),
                    };
                }
            }

            try self.masks.append(self.allocator, .{
                .mask = bitmask,
                .storage_indexes= .{}
            });

            const bitmask_index = self.masks.items.len - 1;
            return .{
                .bitmask_index = @intCast(bitmask_index),
                .in_list_index = 0,
            };
        }

        fn checkIfEntInPool(pool_name: PoolName) bool {
            return pool_name == NAME;
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

        fn validateComponentInArchetype(archetype_mask: MaskManager.Mask, component: CR.ComponentName) !void {
            if(!MaskManager.maskContains(archetype_mask, MaskManager.Runtime.componentToBit(component))) {
                std.debug.print("\nEntity does not have component: {s}\n", .{@tagName(component)});
                return error.ComponentNotInArchetype;
            }
        }

        fn validateEntityInPool(pool_name: PoolName) !void {
            if(!checkIfEntInPool(pool_name)){
                std.debug.print("\nEntity assigned pool '{s}' does not match pool: {s}\n", .{@tagName(pool_name), @tagName(NAME)});
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

test "Basic - all optional components" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{ .name = .GeneralPool, .components = std.meta.tags(CR.ComponentName), .storage_strategy = .SPARSE });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 3, .generation = 0};
    const result = try pool.addEntity(entity, .{.Health = CR.Health{.current = 100, .max = 200}});

    try pool.addComponent(result.storage_index, .Position, .{.x = 0, .y = 0});
    try pool.addComponent(result.storage_index, .Velocity, .{.dx = 0, .dy = 0});
    try pool.removeComponent(result.storage_index, .Velocity);
    try pool.addComponent(result.storage_index, .Attack, .{.damage = 100, .crit_chance = 2});
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
}

test "Pool with required components only" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .req = &.{.Position, .Health},
        .storage_strategy = .SPARSE,
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity1, .{
        .Position = .{.x = 10, .y = 20},
        .Health = .{.current = 50, .max = 100}
    });

    // Verify we can get the components
    const pos = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    try testing.expectEqual(@as(f32, 10), pos.x);
    try testing.expectEqual(@as(f32, 20), pos.y);

    const health = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    try testing.expectEqual(@as(u32, 50), health.current);
    try testing.expectEqual(@as(u32, 100), health.max);
}

test "Pool with mixed required and optional components" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .req = &.{ .Position },
        .components = &.{ .Velocity, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    // Entity with only required component
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const result1 = try pool.addEntity(entity1, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Entity with required + optional components
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const result2 = try pool.addEntity(entity2, .{
        .Position = .{.x = 10, .y = 10},
        .Velocity = .{.dx = 1, .dy = 2},
        .Health = .{.current = 100, .max = 100}
    });

    // Verify entity1 has Position but not Velocity
    _ = try pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Position);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Velocity));
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Health));

    // Verify entity2 has all components
    _ = try pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Velocity);
    _ = try pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Health);
}

test "Error: adding component that already exists" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Try to add Position again - should error
    try testing.expectError(
        error.EntityAlreadyHasComponent,
        pool.addComponent(result.storage_index, .Position, .{.x = 10, .y = 10})
    );
}

test "Error: removing component that doesn't exist" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Try to remove component entity doesn't have - should error
    try testing.expectError(
        error.EntityDoesNotHaveComponent,
        pool.removeComponent(result.storage_index, .Health)
    );
}

test "Error: getting component that doesn't exist" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Try to get component entity doesn't have - should error
    try testing.expectError(
        error.EntityDoesNotHaveComponent,
        pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity)
    );
}

test "Entity removal and slot reuse" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    // Add three entities
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const entity3 = EM.Entity{.index = 3, .generation = 0};

    const result1 = try pool.addEntity(entity1, .{.Position = .{.x = 1, .y = 1}});
    const result2 = try pool.addEntity(entity2, .{.Position = .{.x = 2, .y = 2}});
    const result3 = try pool.addEntity(entity3, .{.Position = .{.x = 3, .y = 3}});

    try testing.expectEqual(@as(u32, 0), result1.storage_index);
    try testing.expectEqual(@as(u32, 1), result2.storage_index);
    try testing.expectEqual(@as(u32, 2), result3.storage_index);

    // Remove middle entity
    try pool.removeEntity(result2.storage_index, SparsePool.NAME);

    // Verify entity2 is gone
    try testing.expectEqual(@as(?EM.Entity, null), pool.storage.entities.items[result2.storage_index]);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Position));

    // Verify entity1 and entity3 still exist
    _ = try pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result3.storage_index, SparsePool.NAME, .Position);

    // Add a new entity - should reuse slot 1 (result2's old slot)
    const entity4 = EM.Entity{.index = 4, .generation = 0};
    const result4 = try pool.addEntity(entity4, .{.Position = .{.x = 4, .y = 4}});

    try testing.expectEqual(result2.storage_index, result4.storage_index); // Should reuse the empty slot

    const pos4 = try pool.getComponent(0, result4.storage_index, SparsePool.NAME, .Position);
    try testing.expectEqual(@as(f32, 4), pos4.x);
}

test "Component modification through pointer" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 10},
        .Health = .{.current = 50, .max = 100}
    });

    // Get component and modify it
    const pos = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    pos.x = 100;
    pos.y = 200;

    // Verify changes persisted
    const pos_check = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    try testing.expectEqual(@as(f32, 100), pos_check.x);
    try testing.expectEqual(@as(f32, 200), pos_check.y);

    // Modify health
    const health = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    health.current = 25;

    const health_check = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    try testing.expectEqual(@as(u32, 25), health_check.current);
}

test "Multiple entities with same component set share bitmask" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    // Create multiple entities with same components
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const entity3 = EM.Entity{.index = 3, .generation = 0};

    const result1 = try pool.addEntity(entity1, .{
        .Position = .{.x = 1, .y = 1},
        .Velocity = .{.dx = 1, .dy = 0}
    });
    const result2 = try pool.addEntity(entity2, .{
        .Position = .{.x = 2, .y = 2},
        .Velocity = .{.dx = 0, .dy = 1}
    });
    const result3 = try pool.addEntity(entity3, .{
        .Position = .{.x = 3, .y = 3},
        .Health = .{.current = 100, .max = 100}
    });

    // Check bitmask maps
    const bm1 = pool.getBitmaskMap(result1.storage_index);
    const bm2 = pool.getBitmaskMap(result2.storage_index);
    const bm3 = pool.getBitmaskMap(result3.storage_index);

    // entity1 and entity2 have same components, should share bitmask_index
    try testing.expectEqual(bm1.bitmask_index, bm2.bitmask_index);

    // entity3 has different components, should have different bitmask_index
    try testing.expect(bm1.bitmask_index != bm3.bitmask_index);

    // Verify the mask group contains both entities
    const mask_entry = pool.masks.items[bm1.bitmask_index];
    try testing.expect(mask_entry.storage_indexes.items.len >= 2);
}

test "Add and remove components dynamically" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity, .Health, .Attack },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 0, .y = 0}
    });

    // Track bitmask changes
    const initial_bm = pool.getBitmaskMap(result.storage_index);

    // Add velocity - should change bitmask
    try pool.addComponent(result.storage_index, .Velocity, .{.dx = 5, .dy = 5});
    const after_vel_bm = pool.getBitmaskMap(result.storage_index);
    try testing.expect(initial_bm.bitmask_index != after_vel_bm.bitmask_index);

    // Add health - should change bitmask again
    try pool.addComponent(result.storage_index, .Health, .{.current = 100, .max = 100});
    const after_health_bm = pool.getBitmaskMap(result.storage_index);
    try testing.expect(after_vel_bm.bitmask_index != after_health_bm.bitmask_index);

    // Add attack
    try pool.addComponent(result.storage_index, .Attack, .{.damage = 50, .crit_chance = 10});

    // Verify all components exist
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Attack);

    // Now remove components one by one
    try pool.removeComponent(result.storage_index, .Attack);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result.storage_index, SparsePool.NAME, .Attack));

    try pool.removeComponent(result.storage_index, .Velocity);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity));

    // Position and Health should still exist
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
}

test "SwapRemove correctly updates bitmask_map indices" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    // Create 3 entities with the same component set (they'll share a mask group)
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const entity3 = EM.Entity{.index = 3, .generation = 0};

    const result1 = try pool.addEntity(entity1, .{
        .Position = .{.x = 1, .y = 1},
        .Velocity = .{.dx = 1, .dy = 0}
    });
    const result2 = try pool.addEntity(entity2, .{
        .Position = .{.x = 2, .y = 2},
        .Velocity = .{.dx = 0, .dy = 1}
    });
    const result3 = try pool.addEntity(entity3, .{
        .Position = .{.x = 3, .y = 3},
        .Velocity = .{.dx = 1, .dy = 1}
    });

    // All should share the same bitmask
    const bm1 = pool.getBitmaskMap(result1.storage_index);
    const bm2 = pool.getBitmaskMap(result2.storage_index);
    const bm3 = pool.getBitmaskMap(result3.storage_index);

    try testing.expectEqual(bm1.bitmask_index, bm2.bitmask_index);
    try testing.expectEqual(bm1.bitmask_index, bm3.bitmask_index);

    // Their in_list_index should be 0, 1, 2 respectively
    try testing.expectEqual(@as(u32, 0), bm1.in_list_index);
    try testing.expectEqual(@as(u32, 1), bm2.in_list_index);
    try testing.expectEqual(@as(u32, 2), bm3.in_list_index);

    // Remove the middle entity (result2) - this should swap result3 into result2's position
    try pool.removeEntity(result2.storage_index, SparsePool.NAME);

    // result3 should now have in_list_index of 1 (swapped into result2's old spot)
    const bm3_after = pool.getBitmaskMap(result3.storage_index);
    try testing.expectEqual(@as(u32, 1), bm3_after.in_list_index);

    // result1 should be unchanged
    const bm1_after = pool.getBitmaskMap(result1.storage_index);
    try testing.expectEqual(@as(u32, 0), bm1_after.in_list_index);

    // Verify the storage_indexes list is correct
    const mask_entry = pool.masks.items[bm1.bitmask_index];
    try testing.expectEqual(@as(usize, 2), mask_entry.storage_indexes.items.len);
    try testing.expectEqual(result1.storage_index, mask_entry.storage_indexes.items[0]);
    try testing.expectEqual(result3.storage_index, mask_entry.storage_indexes.items[1]);
}

test "Migration queue flush" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity },
        .storage_strategy = .SPARSE
    });
    var pool = SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 0, .generation = 0};
    const result = try pool.addEntity(entity, .{.Position = .{.x = 3, .y = 2}});

    // Get mask before adding component
    const bm_before = pool.getBitmaskMap(result.storage_index);
    const mask_before = pool.masks.items[bm_before.bitmask_index].mask;

    // Queue a component add via migration queue
    try pool.addOrRemoveComponent(
        entity,
        result.archetype_index,
        SparsePool.NAME,
        result.storage_index,
        false,
        .adding,
        .Velocity,
        .{.dx = 1, .dy = 1}
    );

    // Flush the migration queue
    const results = try pool.flushMigrationQueue();
    defer allocator.free(results);

    // Verify migration result
    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expect(std.meta.eql(results[0].entity, entity));

    // Verify mask changed after flush
    const bm_after = pool.getBitmaskMap(result.storage_index);
    const mask_after = pool.masks.items[bm_after.bitmask_index].mask;
    try testing.expect(mask_before != mask_after);

    // Verify component is accessible
    const vel = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity);
    try testing.expectEqual(@as(f32, 1), vel.dx);
    try testing.expectEqual(@as(f32, 1), vel.dy);
}
