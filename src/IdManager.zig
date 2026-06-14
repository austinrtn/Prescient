const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Registry = @import("Registry.zig").Registry;
const EntityId = Registry.EntityId;

pub const IdSlot = struct {
    entity_id: EntityId,
    pool_id: PR.Enum,
    group_index: Registry.GroupIndex,
    member_index: Registry.MemberIndex,
};

pub const IdManager = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    slots: ArrayList(IdSlot) = .empty,
    queue: ArrayList(EntityId) = .empty,
    count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        const self: Self = .{ .allocator = allocator };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.slots.deinit(self.allocator);
        self.queue.deinit(self.allocator);
    }

    pub fn getNextSlot(self: *Self) IdSlot {
        if (self.queue.pop()) |entity_id| return self.slots.items[entity_id.idx()];

        const entity_id: EntityId = .init(self.slots.items.len);
        return .{
            .entity_id = entity_id,
            .pool_id = undefined,
            .group_index = undefined,
            .member_index = undefined,
        };
    }

    pub fn setSlot(self: *Self, slot: IdSlot) !void {
        self.assertSlotNotInQueue(slot.entity_id);
        if (slot.entity_id.idx() < self.slots.items.len) self.slots.items[slot.entity_id.idx()] = slot else try self.slots.append(self.allocator, slot);
    }

    pub fn getSlot(self: *Self, entity_id: EntityId) IdSlot {
        self.assertSlotNotInQueue(entity_id);
        return self.slots.items[entity_id.idx()];
    }

    pub fn sendSlotToQueue(self: *Self, entity_id: EntityId) !void {
        self.assertSlotNotInQueue(entity_id);
        try self.queue.append(self.allocator, entity_id);
    }

    fn assertSlotNotInQueue(self: *Self, entity_id: EntityId) void {
        if(comptime builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
            for (self.queue.items) |queued_entity_id| {
                if(queued_entity_id.eql(entity_id))
                    std.debug.panic("\n\nERROR: Entity ID {} is inactive.  Are you trying to operate on an already deleted entity?\n", .{queued_entity_id.val});
            }
        }
    }
};
