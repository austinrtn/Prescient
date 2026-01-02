// Entity Operation Queue
// Queues entity creation and destruction operations for deferred processing.
// This allows queries to use direct slices safely - storage won't change during iteration.
//
// Usage flow:
// 1. createEntity() reserves entity slot and queues create with component data
// 2. destroyEntity() marks entity pending and queues destruction
// 3. flushEntityOperations() processes all queued ops before systems run
//
// Destroys are processed first (in reverse storage order to avoid index invalidation),
// then creates are processed.

const std = @import("std");
const CR = @import("../registries/ComponentRegistry.zig");
const EM = @import("EntityManager.zig");

const ArrayList = std.ArrayList;
const Entity = EM.Entity;

pub const EntityOperationType = enum {
    create,
    destroy,
};

/// Result of flushing entity operations
pub const EntityOperationResult = struct {
    operation: EntityOperationType,
    entity: Entity,
    storage_index: u32,
    mask_list_index: u32,
    swapped_entity: ?Entity, // Only for archetype pool destroys
};

pub fn EntityOperationQueueType(comptime BuilderType: type) type {
    return struct {
        const Self = @This();

        pub const CreateEntry = struct {
            entity: Entity,
            component_data: BuilderType,
        };

        pub const DestroyEntry = struct {
            entity: Entity,
            storage_index: u32,
            mask_list_index: u32,
        };

        allocator: std.mem.Allocator,
        create_queue: ArrayList(CreateEntry),
        destroy_queue: ArrayList(DestroyEntry),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .create_queue = ArrayList(CreateEntry){},
                .destroy_queue = ArrayList(DestroyEntry){},
            };
        }

        pub fn queueCreate(self: *Self, entity: Entity, component_data: BuilderType) !void {
            try self.create_queue.append(self.allocator, .{
                .entity = entity,
                .component_data = component_data,
            });
        }

        pub fn queueDestroy(self: *Self, entity: Entity, storage_index: u32, mask_list_index: u32) !void {
            // Check if entity is in create queue (created then destroyed same frame)
            for (self.create_queue.items, 0..) |entry, i| {
                if (std.meta.eql(entry.entity, entity)) {
                    // Remove from create queue instead of queueing destroy
                    _ = self.create_queue.swapRemove(i);
                    return;
                }
            }

            try self.destroy_queue.append(self.allocator, .{
                .entity = entity,
                .storage_index = storage_index,
                .mask_list_index = mask_list_index,
            });
        }

        pub fn hasQueuedOperations(self: *const Self) bool {
            return self.create_queue.items.len > 0 or self.destroy_queue.items.len > 0;
        }

        pub fn clear(self: *Self) void {
            self.create_queue.clearRetainingCapacity();
            self.destroy_queue.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.create_queue.deinit(self.allocator);
            self.destroy_queue.deinit(self.allocator);
        }
    };
}
