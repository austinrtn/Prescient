const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const ComponentName = ComponentRegistry.ComponentName;
const getComponentByName = ComponentRegistry.GetComponentByName;
const PoolName = @import("../registries/PoolRegistry.zig").PoolName;

pub const EntityManagerErrors = error{NoAvailableEntities};

pub const Entity = struct {
    index: u32,
    generation: u32,
};

pub const EntitySlot = struct {
    index: u32,
    generation: u32 = 0,
    is_migrating: bool = false,
    is_pending_create: bool = false,  // Entity reserved but not yet in storage
    is_pending_destroy: bool = false, // Entity queued for destruction

    pool_name: PoolName = undefined,
    mask_list_index: u32 = undefined,
    storage_index: u32 = undefined,

    pub fn getEntity(self: *@This()) Entity {
        return .{ .index = self.index, .generation = self.generation };
    }
};

pub const EntityManager = struct {
    const Self = @This();

    allocator: Allocator,
    entity_slots: ArrayList(EntitySlot),
    available_entities: ArrayList(usize),

    pub fn init(allocator: Allocator) !Self {
        const entity_manager: Self = .{
            .allocator = allocator,
            .entity_slots = .{},
            .available_entities = .{},
        };

        return entity_manager;
    }

    pub fn getSlot(self: *Self, entity: Entity) !*EntitySlot {
        const slot = &self.entity_slots.items[entity.index];
        if (slot.generation != entity.generation) return error.StaleEntity;
        if (slot.is_pending_create) return error.EntityPendingCreate;
        if (slot.is_pending_destroy) return error.EntityPendingDestroy;
        return slot;
    }

    /// Get slot without checking pending flags - for internal use during flush
    pub fn getSlotUnchecked(self: *Self, entity: Entity) !*EntitySlot {
        const slot = &self.entity_slots.items[entity.index];
        if (slot.generation != entity.generation) return error.StaleEntity;
        return slot;
    }

    pub fn getNewSlot(
            self: *Self,
            pool_name: PoolName,
            mask_list_index: u32,
            storage_index: u32,
        ) !*EntitySlot {
        const index = if (self.available_entities.pop()) |indx|
            indx
        else blk: {
            const new_index = @as(u32, @intCast(self.entity_slots.items.len));
            try self.entity_slots.append(self.allocator, .{
                .index = new_index,
                .generation = 0,
                .pool_name = pool_name,
                .mask_list_index = mask_list_index,
                .storage_index = storage_index,
            });
            break :blk new_index;
        };

        const slot = &self.entity_slots.items[index];
        return slot;
    }

    /// Reserve a slot for a pending entity creation.
    /// The entity handle is valid but marked as pending until finalized.
    pub fn getNewPendingSlot(self: *Self, pool_name: PoolName) !*EntitySlot {
        const index = if (self.available_entities.pop()) |indx|
            indx
        else blk: {
            const new_index = @as(u32, @intCast(self.entity_slots.items.len));
            try self.entity_slots.append(self.allocator, .{
                .index = new_index,
                .generation = 0,
                .pool_name = pool_name,
                .mask_list_index = undefined,
                .storage_index = undefined,
                .is_pending_create = true,
            });
            break :blk new_index;
        };

        const slot = &self.entity_slots.items[index];
        slot.pool_name = pool_name;
        slot.is_pending_create = true;
        slot.is_pending_destroy = false;
        return slot;
    }

    /// Finalize a pending slot after entity is actually created in storage.
    pub fn finalizePendingSlot(slot: *EntitySlot, mask_list_index: u32, storage_index: u32) void {
        slot.mask_list_index = mask_list_index;
        slot.storage_index = storage_index;
        slot.is_pending_create = false;
    }

    pub fn remove(self: *Self, slot: *EntitySlot) !void {
        slot.generation +%= 1;
        slot.is_pending_create = false;
        slot.is_pending_destroy = false;
        try self.available_entities.append(self.allocator, slot.index);
    }

    pub fn deinit(self: *Self) void {
        self.entity_slots.deinit(self.allocator);
        self.available_entities.deinit(self.allocator);
    }
};

// test "EntityManager - init and deinit" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     // Should start with no slots and no available entities
//     try std.testing.expectEqual(0, manager.entity_slots.items.len);
//     try std.testing.expectEqual(0, manager.available_entities.items.len);
// }
//
// test "EntityManager - getNewSlot creates first entity" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     const pool_id: Mask = 1;
//     const mask: Mask = 3;
//     const storage_index: u32 = 0;
//
//     const slot = try manager.getNewSlot(storage_index, pool_id, mask);
//
//     // Should have created one slot
//     try std.testing.expectEqual(1, manager.entity_slots.items.len);
//
//     // Verify slot data
//     try std.testing.expectEqual(0, slot.index);
//     try std.testing.expectEqual(0, slot.generation);
//     try std.testing.expectEqual(pool_id, slot.pool_id);
//     try std.testing.expectEqual(mask, slot.mask);
//     try std.testing.expectEqual(storage_index, slot.storage_index);
// }
//
// test "EntityManager - getNewSlot creates multiple entities" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     const slot1 = try manager.getNewSlot(0, 1, 3);
//     const slot2 = try manager.getNewSlot(1, 2, 5);
//     const slot3 = try manager.getNewSlot(2, 3, 7);
//
//     // Should have three slots
//     try std.testing.expectEqual(3, manager.entity_slots.items.len);
//
//     // Verify indices are sequential
//     try std.testing.expectEqual(0, slot1.index);
//     try std.testing.expectEqual(1, slot2.index);
//     try std.testing.expectEqual(2, slot3.index);
//
//     // All should start at generation 0
//     try std.testing.expectEqual(0, slot1.generation);
//     try std.testing.expectEqual(0, slot2.generation);
//     try std.testing.expectEqual(0, slot3.generation);
// }
//
// test "EntityManager - getEntity returns correct Entity" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     const slot = try manager.getNewSlot(0, 1, 3);
//     const entity = slot.getEntity();
//
//     try std.testing.expectEqual(slot.index, entity.index);
//     try std.testing.expectEqual(slot.generation, entity.generation);
// }
//
// test "EntityManager - getSlot retrieves correct slot" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     const slot1 = try manager.getNewSlot(0, 1, 3);
//     const slot2 = try manager.getNewSlot(1, 2, 5);
//
//     const entity1 = slot1.getEntity();
//     const entity2 = slot2.getEntity();
//
//     const retrieved1 = try manager.getSlot(entity1);
//     const retrieved2 = try manager.getSlot(entity2);
//
//     // Should retrieve the same slots
//     try std.testing.expectEqual(slot1.index, retrieved1.index);
//     try std.testing.expectEqual(slot2.index, retrieved2.index);
//     try std.testing.expectEqual(slot1.generation, retrieved1.generation);
//     try std.testing.expectEqual(slot2.generation, retrieved2.generation);
// }
//
// test "EntityManager - remove increments generation" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     const slot = try manager.getNewSlot(0, 1, 3);
//     try std.testing.expectEqual(0, slot.generation);
//
//     try manager.remove(slot);
//
//     // Generation should be incremented
//     try std.testing.expectEqual(1, slot.generation);
//
//     // Index should be added to available_entities
//     try std.testing.expectEqual(1, manager.available_entities.items.len);
//     try std.testing.expectEqual(0, manager.available_entities.items[0]);
// }
//
// test "EntityManager - remove and reuse slot" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     // Create and remove an entity
//     const slot1 = try manager.getNewSlot(0, 1, 3);
//     const entity1 = slot1.getEntity();
//     try std.testing.expectEqual(0, entity1.index);
//     try std.testing.expectEqual(0, entity1.generation);
//
//     try manager.remove(slot1);
//     try std.testing.expectEqual(1, slot1.generation);
//
//     // Create a new entity - should reuse the slot
//     const slot2 = try manager.getNewSlot(1, 2, 5);
//
//     // Should be the same index but different generation
//     try std.testing.expectEqual(0, slot2.index);
//     try std.testing.expectEqual(1, slot2.generation);
//
//     // available_entities should be empty now
//     try std.testing.expectEqual(0, manager.available_entities.items.len);
//
//     // Total slots should still be 1 (reused)
//     try std.testing.expectEqual(1, manager.entity_slots.items.len);
// }
//
// test "EntityManager - getSlot rejects stale entity" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     const slot = try manager.getNewSlot(0, 1, 3);
//     const old_entity = slot.getEntity();
//
//     // Remove the entity (increments generation)
//     try manager.remove(slot);
//
//     // Try to get slot with old entity - should fail
//     const result = manager.getSlot(old_entity);
//     try std.testing.expectError(error.StaleEntity, result);
// }
//
// test "EntityManager - generation wraps around" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     const slot = try manager.getNewSlot(0, 1, 3);
//
//     // Set generation to max value
//     slot.generation = std.math.maxInt(u32);
//
//     // Remove should wrap around using +%=
//     try manager.remove(slot);
//
//     try std.testing.expectEqual(0, slot.generation);
// }
//
// test "EntityManager - multiple remove and reuse cycles" {
//     const allocator = std.testing.allocator;
//     var manager = try EntityManager.init(allocator);
//     defer manager.deinit();
//
//     // Create 3 entities
//     _ = try manager.getNewSlot(0, 1, 3);
//     const slot2 = try manager.getNewSlot(1, 2, 5);
//     const slot3 = try manager.getNewSlot(2, 3, 7);
//
//     try std.testing.expectEqual(3, manager.entity_slots.items.len);
//
//     // Remove middle entity
//     try manager.remove(slot2);
//     try std.testing.expectEqual(1, manager.available_entities.items.len);
//
//     // Remove last entity
//     try manager.remove(slot3);
//     try std.testing.expectEqual(2, manager.available_entities.items.len);
//
//     // Create new entity - should reuse slot3's index (last removed, last popped)
//     const slot4 = try manager.getNewSlot(3, 4, 9);
//     try std.testing.expectEqual(2, slot4.index);
//     try std.testing.expectEqual(1, slot4.generation);
//
//     // Create another - should reuse slot2's index
//     const slot5 = try manager.getNewSlot(4, 5, 11);
//     try std.testing.expectEqual(1, slot5.index);
//     try std.testing.expectEqual(1, slot5.generation);
//
//     // All available slots should be used
//     try std.testing.expectEqual(0, manager.available_entities.items.len);
//
//     // Still only 3 total slots
//     try std.testing.expectEqual(3, manager.entity_slots.items.len);
// }
