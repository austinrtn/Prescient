const std = @import("std");
const AP = @import("ArchetypePool.zig");
const PR = @import("PoolRegistry.zig");
const PM = @import("PoolManager.zig");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const testing = std.testing;
const EM = @import("EntityManager.zig");

pub const PoolConfig = struct {
    name: PR.PoolName,
    req: []const CR.ComponentName,
    opt: []const CR.ComponentName,
};

pub fn PoolInterfaceType(comptime config: PoolConfig) type {
    return struct {
        const Self = @This();
        const Pool = AP.ArchetypePoolType(config.req, config.opt, config.name);

        pool: *Pool,
        entity_manager: *EM.EntityManager,

        /// EntityBuilder type for creating entities in this pool
        /// Required components are non-optional fields
        /// Optional components are nullable fields with null defaults
        pub const Builder = Pool.Builder;

        pub fn init(pool: *Pool, entity_manager: *EM.EntityManager) Self{
            return Self{
                .pool = pool,
                .entity_manager = entity_manager,
            };
        }

        pub fn createEntity(self: *Self, comptime component_data: Builder) !EM.Entity {
            const pool_mask = @TypeOf(self.pool.*).pool_mask;
            var entity_slot = try self.entity_manager.getNewSlot(undefined, pool_mask, undefined);

            const result = try self.pool.addEntity(entity_slot.getEntity(), component_data);
            entity_slot.storage_index = result.storage_index;
            entity_slot.mask_list_index = result.archetype_index;
            entity_slot.pool_name = Pool.NAME;

            return entity_slot.getEntity();
        }

        pub fn destroyEntity(self: *Self, entity: EM.Entity) !void {
            const entity_slot = try self.entity_manager.getSlot(entity);
            const swapped_entity = try self.pool.removeEntity(entity_slot.mask_list_index, entity_slot.storage_index, entity_slot.pool_name);

            if(!std.meta.eql(entity_slot.getEntity(), swapped_entity)) {
                const swapped_slot = try self.entity_manager.getSlot(swapped_entity);
                swapped_slot.storage_index = entity_slot.storage_index;
            }
            try self.entity_manager.remove(entity_slot);
        }

        pub fn getComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !*CR.getTypeByName(component){
            const entity_slot = try self.entity_manager.getSlot(entity);
            return self.pool.getComponent(entity_slot.mask_list_index, entity_slot.storage_index, entity_slot.pool_name, component);
        }

        pub fn addComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void {
            const entity_slot = try self.entity_manager.getSlot(entity);
            try self.pool.addOrRemoveComponent(
                entity,
                entity_slot.mask_list_index,
                entity_slot.pool_name,
                entity_slot.storage_index,
                entity_slot.is_migrating,
                .adding,
                component,
                data
            );
            entity_slot.is_migrating = true;
        }

        pub fn removeComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !void {
            const entity_slot = try self.entity_manager.getSlot(entity);
            try self.pool.addOrRemoveComponent(
                entity,
                entity_slot.mask_list_index,
                entity_slot.pool_name,
                entity_slot.storage_index,
                entity_slot.is_migrating,
                .removing,
                component,
                null,
            );
            entity_slot.is_migrating = true;
        }

        pub fn flushMigrationQueue(self: *Self) !void {
            const results = try self.pool.flushMigrationQueue();
            defer self.entity_manager.allocator.free(results);

            for (results) |result| {
                const slot = try self.entity_manager.getSlot(result.entity);
                slot.storage_index = result.archetype_index;
                slot.mask_list_index = result.mask_list_index;
                slot.is_migrating = false;

                // Update swapped entity's storage index if a swap occurred
                if (result.swapped_entity) |swapped| {
                    const swapped_slot = try self.entity_manager.getSlot(swapped);
                    swapped_slot.storage_index = slot.storage_index;
                }
            }
        }
    };
}

test "flush" {
    const allocator = testing.allocator;
    var entity_manager = try EM.EntityManager.init(allocator);
    var pool_manager = PM.PoolManager.init(allocator);
    const movement_pool = try pool_manager.getOrCreatePool(.MovementPool);
    defer {
        pool_manager.deinit();
        entity_manager.deinit();
    }
    var interface = PoolInterfaceType(PoolConfig{ .name = .MovementPool, .req = &.{}, .opt = &.{.Position, .Velocity}}).init(movement_pool, &entity_manager);

    const ent = try interface.createEntity(.{.Position = CR.Position{.x = 3, .y = 4}});
    const slot = try interface.entity_manager.getSlot(ent);
    const mask_before = movement_pool.mask_list.items[slot.mask_list_index];
    try testing.expect(mask_before == 1);
    try interface.addComponent(ent, .Velocity, .{.dx = 4, .dy = 0});
    try interface.flushMigrationQueue();
    const mask_after = movement_pool.mask_list.items[slot.mask_list_index];
    try testing.expect(mask_after == 3);
}
//
// test "create entity and add component" {
//     var entity_manager = try EM.EntityManager.init(testing.allocator);
//     const MovementPool = AP.ArchetypePool(&.{}, &.{.Position, .Velocity}, .Misc);
//     var movement_pool = try MovementPool.init(testing.allocator);
//
//     defer {
//         entity_manager.deinit();
//         movement_pool.deinit();
//     }
//
//     const config = PoolConfig{ .req = &.{}, .opt = &.{.Position, .Velocity} };
//     var interface = PoolInterface(config).init(&movement_pool, &entity_manager);
//
//     const entity1 = try interface.createEntity(.{
//         .Position = .{.x = 3, .y = 4}
//     });
//
//
//     const entity2 = try interface.createEntity(.{
//         .Position = .{.x = 1, .y = 0},
//     });
//
//     // Before adding component, verify entity1 has only Position
//     const slot1_before = try interface.entity_manager.getSlot(entity1);
//     const slot2_before = try interface.entity_manager.getSlot(entity2);
//
//     try testing.expect(slot1_before.storage_index == 0);
//     try testing.expect(slot2_before.storage_index == 1);
//     // Note: Both entities are in the same pool (pool_mask=3), but entity1 only has Position
//     // so its mask should be 1, while entity2 also only has Position so mask should be 1
//
//     try interface.addComponent(
//         entity1,
//         .Velocity,
//         .{.dx = 1, .dy = 2},
//     );
//
//     // After adding component, verify entity1 now has both Position and Velocity
//     const slot1_after = try interface.entity_manager.getSlot(entity1);
//     const slot2_after = try interface.entity_manager.getSlot(entity2);
//
//     // Verify that entity1 now has both Position and Velocity components
//     try testing.expect(slot1_after.mask == 3); // Position (bit 0) + Velocity (bit 1) = 3
//
//     // Verify entity2 still only has Position component
//     try testing.expect(slot2_after.mask == 1); // Only Position component
//     try testing.expect(slot2_after.mask == slot2_before.mask); // Entity2's mask unchanged
//
//     // Verify that entity1 and entity2 now have different masks
//     try testing.expect(slot1_after.mask != slot2_after.mask);
//
//     // Verify that entity2's storage_index was updated after entity1 was moved via swap-remove
//     try testing.expect(slot2_after.storage_index == 0);
//
//     // Verify entity1 has new storage index after being moved to new archetype
//     try testing.expect(slot1_after.storage_index == 0);
// }
//
//
// test "remove component" {
//     var entity_manager = try EM.EntityManager.init(testing.allocator);
//     const MovementPool = AP.ArchetypePool(&.{}, &.{.Position, .Velocity}, .Misc);
//     var movement_pool = try MovementPool.init(testing.allocator);
//
//     defer {
//         entity_manager.deinit();
//         movement_pool.deinit();
//     }
//
//     const config = PoolConfig{ .req = &.{}, .opt = &.{.Position, .Velocity} };
//     var interface = PoolInterface(config).init(&movement_pool, &entity_manager);
//
//     const entity1 = try interface.createEntity(.{
//         .Position = .{.x = 3, .y = 4},
//         .Velocity = .{.dx = 1, .dy = 0},
//     });
//
//     const slot = try interface.entity_manager.getSlot(entity1);
//     try testing.expect(slot.mask == 3);
//
//     try interface.removeComponent(entity1, .Velocity);
//     try testing.expect(slot.mask == 1);
// }
//
// test "get component" {
//     var entity_manager = try EM.EntityManager.init(testing.allocator);
//     const MovementPool = AP.ArchetypePool(&.{}, &.{.Position, .Velocity}, .Misc);
//     var movement_pool = try MovementPool.init(testing.allocator);
//
//     defer {
//         entity_manager.deinit();
//         movement_pool.deinit();
//     }
//
//     const config = PoolConfig{ .req = &.{}, .opt = &.{.Position, .Velocity} };
//     var interface = PoolInterface(config).init(&movement_pool, &entity_manager);
//
//     const entity1 = try interface.createEntity(.{
//         .Position = .{.x = 3, .y = 4},
//     });
//     
//     const pos_data: *CR.Position = try interface.getComponent(entity1, .Position);
//     try testing.expect(pos_data.x == 3);
//     try testing.expect(pos_data.y == 4);
//     
//     pos_data.x = 0;
//
//     const pos_data_second_attempt = try interface.getComponent(entity1, .Position);
//     try testing.expect(pos_data_second_attempt.x == 0);
//
//     try testing.expectError(error.ComponentNotInArchetype, interface.getComponent(entity1, .Velocity));
// }
//
// test "destroy Entity" {
//     var entity_manager = try EM.EntityManager.init(testing.allocator);
//     const MovementPool = AP.ArchetypePool(&.{}, &.{.Position, .Velocity}, .Misc);
//     var movement_pool = try MovementPool.init(testing.allocator);
//
//     defer {
//         entity_manager.deinit();
//         movement_pool.deinit();
//     }
//
//     const config = PoolConfig{ .req = &.{}, .opt = &.{.Position, .Velocity} };
//     var movement_interface = PoolInterface(config).init(&movement_pool, &entity_manager);
//
//     var entities: [3]EM.Entity = undefined;
//     for(0..entities.len) |i| {
//         const entity = try movement_interface.createEntity(.{
//             .Position = .{.x = 0, .y = 0},
//         });
//         entities[i] = entity;
//     } 
//
//     var slots: [entities.len]*EM.EntitySlot = undefined; for(entities, 0..) |ent, i| {
//         const slot = try movement_interface.entity_manager.getSlot(ent);
//         slots[i] = slot;
//     }
//
//     try movement_interface.destroyEntity(entities[1]);
//     entities[1] = try movement_interface.createEntity(.{.Position = .{.x = 4, .y = 0},});
//     
//     try testing.expect(slots[0].storage_index == 0);
//     try testing.expect(slots[1].generation == 1);
//     try testing.expect(slots[1].storage_index == 2);
//     try testing.expect(slots[2].storage_index == 1);
// }
//
// test "catch pool mismatch bug" {
//     var entity_manager = try EM.EntityManager.init(testing.allocator);
//     const MovementPool = AP.ArchetypePool(&.{}, &.{.Position, .Velocity}, .Misc);
//     const AllPool = AP.ArchetypePool(&.{}, &.{.Position, .Velocity, .Attack}, .Misc);
//     var movement_pool = try MovementPool.init(testing.allocator);
//     var all_pool = try AllPool.init(testing.allocator);
//
//     defer {
//         entity_manager.deinit();
//         movement_pool.deinit();
//         all_pool.deinit();
//     }
//
//     const movement_config = PoolConfig{ .req = &.{}, .opt = &.{.Position, .Velocity} };
//     const all_config = PoolConfig{ .req = &.{}, .opt = &.{.Position, .Velocity, .Attack} };
//     var movement_interface = PoolInterface(movement_config).init(&movement_pool, &entity_manager);
//     var all_interface = PoolInterface(all_config).init(&all_pool, &entity_manager);
//
//     const move_ent = try movement_interface.createEntity(.{
//         .Position = .{.x = 3, .y = 2},
//         .Velocity = .{.dx = 1, .dy = 1},
//     });
//
//     const all_ent = try all_interface.createEntity(.{
//         .Position = .{.x = 1, .y = 9},
//         .Velocity = .{.dx = 0, .dy = 0},
//         .Attack = .{.damage = 20.0, .crit_chance = 50},
//     });
//     _ = all_ent;
//
//     try testing.expectError(error.EntityPoolMismatch, all_interface.addComponent(move_ent, .Attack, .{.damage = 5, .crit_chance = 12}));
// }
