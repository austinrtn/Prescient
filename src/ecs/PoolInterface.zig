const std = @import("std");
const AP = @import("ArchetypePool.zig");
const PR = @import("PoolRegistry.zig");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const testing = std.testing;

const EM = @import("EntityManager.zig");
pub fn PoolInterface(comptime components: []const CR.ComponentName, comptime optimize: bool) type {
    return struct {
        const Self = @This();
        pool: *AP.ArchetypePool(components, optimize),
        entity_manager: *EM.EntityManager,

        pub fn init(pool: *AP.ArchetypePool(components, optimize), entity_manager: *EM.EntityManager) Self{
            return Self{
                .pool = pool,
                .entity_manager = entity_manager,
            };
        }

        pub fn createEntity(self: *Self, comptime component_data: anytype) !EM.Entity {
            const pool_mask = @TypeOf(self.pool.*).pool_mask;
            var entity_slot = try self.entity_manager.getNewSlot(undefined, pool_mask, undefined);
            const result = try self.pool.addEntity(entity_slot.getEntity(), component_data);
            entity_slot.storage_index = result.index;
            entity_slot.mask = result.mask;
            entity_slot.pool_mask = pool_mask;
            return entity_slot.getEntity();
        }

        pub fn destroyEntity(self: *Self, entity: EM.Entity) !void {
            const entity_slot = try self.entity_manager.getSlot(entity);
            const swapped_entity = try self.pool.remove_entity(entity_slot.storage_index, entity_slot.mask, entity_slot.pool_mask);
            
            if(std.meta.eql(entity_slot.getEntity(), swapped_entity)) {
                const swapped_slot = try self.entity_manager.getSlot(swapped_entity);
                swapped_slot.storage_index = entity_slot.storage_index; 
            }
            try self.entity_manager.remove(entity_slot);
        }

        pub fn addComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void {
            var entity_slot = try self.entity_manager.getSlot(entity);
            const result = try self.pool.addComponent(entity_slot.mask, entity_slot.pool_mask, entity_slot.storage_index, component, data);
            const old_storage_index = entity_slot.storage_index;
            entity_slot.mask = result.added_entity_mask;
            entity_slot.storage_index = result.added_entity_index;

            if(result.swapped_entity) |swapped_ent|{
                const swapped_slot = try self.entity_manager.getSlot(swapped_ent);
                swapped_slot.storage_index = old_storage_index;
            }
        }

        // pub fn removeComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !void {
        //
        // }
    };
}

test "create entity" {
    var entity_manager = try EM.EntityManager.init(testing.allocator);
    const MovementPool = AP.ArchetypePool(&.{.Position, .Velocity}, false);
    var movement_pool = try MovementPool.init(testing.allocator);

    defer {
        entity_manager.deinit();
        movement_pool.deinit();
    }

    var interface = PoolInterface(MovementPool.COMPONENTS, false).init(&movement_pool, &entity_manager);

    const entity1 = try interface.createEntity(.{
        .Position = .{.x = 3, .y = 4}
    });


    const entity2 = try interface.createEntity(.{
        .Position = .{.x = 1, .y = 0},
    });

    // Before adding component, verify entity1 has only Position
    const slot1_before = try interface.entity_manager.getSlot(entity1);
    const slot2_before = try interface.entity_manager.getSlot(entity2);

    try testing.expect(slot1_before.storage_index == 0);
    try testing.expect(slot2_before.storage_index == 1);
    // Note: Both entities are in the same pool (pool_mask=3), but entity1 only has Position
    // so its mask should be 1, while entity2 also only has Position so mask should be 1

    try interface.addComponent(
        entity1,
        .Velocity,
        .{.dx = 1, .dy = 2},
    );


    // After adding component, verify entity1 now has both Position and Velocity
    const slot1_after = try interface.entity_manager.getSlot(entity1);
    const slot2_after = try interface.entity_manager.getSlot(entity2);

    // Verify that entity1 now has both Position and Velocity components
    try testing.expect(slot1_after.mask == 3); // Position (bit 0) + Velocity (bit 1) = 3

    // Verify entity2 still only has Position component
    try testing.expect(slot2_after.mask == 1); // Only Position component
    try testing.expect(slot2_after.mask == slot2_before.mask); // Entity2's mask unchanged

    // Verify that entity1 and entity2 now have different masks
    try testing.expect(slot1_after.mask != slot2_after.mask);

    // Verify that entity2's storage_index was updated after entity1 was moved via swap-remove
    try testing.expect(slot2_after.storage_index == 0);

    // Verify entity1 has new storage index after being moved to new archetype
    try testing.expect(slot1_after.storage_index == 0);
}

test "destroy Entity" {
    var entity_manager = try EM.EntityManager.init(testing.allocator);
    const MovementPool = AP.ArchetypePool(&.{.Position, .Velocity}, false);
    var movement_pool = try MovementPool.init(testing.allocator);

    defer {
        entity_manager.deinit();
        movement_pool.deinit();
    }

    var movement_interface = PoolInterface(MovementPool.COMPONENTS, false).init(&movement_pool, &entity_manager);

    var entities: [3]EM.Entity = undefined;
    for(0..entities.len) |i| {
        const entity = try movement_interface.createEntity(.{
            .Position = .{.x = 0, .y = 0},
        });
        entities[i] = entity;
    } 
    var slots: [entities.len]*EM.EntitySlot = undefined;
    for(entities, 0..) |ent, i| {
        const slot = try movement_interface.entity_manager.getSlot(ent);
        slots[i] = slot;
    }


    try movement_interface.destroyEntity(entities[1]);

    std.debug.print("\n\n{any}\n\n", .{movement_interface.entity_manager.available_entities});
}

test "catch pool mismatch bug" {
    var entity_manager = try EM.EntityManager.init(testing.allocator);
    const MovementPool = AP.ArchetypePool(&.{.Position, .Velocity}, false);
    const AllPool = AP.ArchetypePool(&.{.Position, .Velocity, .Attack}, false);
    var movement_pool = try MovementPool.init(testing.allocator);
    var all_pool = try AllPool.init(testing.allocator);

    defer {
        entity_manager.deinit();
        movement_pool.deinit();
        all_pool.deinit();
    }

    var movement_interface = PoolInterface(MovementPool.COMPONENTS, false).init(&movement_pool, &entity_manager);
    var all_interface = PoolInterface(AllPool.COMPONENTS, false).init(&all_pool, &entity_manager);

    const move_ent = try movement_interface.createEntity(.{
        .Position = .{.x = 3, .y = 2},
        .Velocity = .{.dx = 1, .dy = 1},
    });

    const all_ent = try all_interface.createEntity(.{
        .Position = .{.x = 1, .y = 9},
        .Velocity = .{.dx = 0, .dy = 0},
        .Attack = .{.damage = 20.0, .crit_chance = 50},
    });
    _ = all_ent;

    try testing.expectError(error.EntityPoolMismatch, all_interface.addComponent(move_ent, .Attack, .{.damage = 5, .crit_chance = 12}));
}
