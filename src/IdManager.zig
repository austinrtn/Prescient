const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Registry = @import("Registry.zig").Registry;

pub const IdSlot = struct {
    entity_id: Registry.EntityId,
    pool_id: PR.Enum,
    group_index: Registry.GroupIndex,
    member_index: Registry.MemberIndex,
};

pub const IdManager = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    slots: ArrayList(IdSlot) = .empty,
    queue: ArrayList(Registry.EntityId) = .empty,
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

        const entity_id: Registry.EntityId = .init(@intCast(self.slots.items.len));
        return .{
            .entity_id = entity_id,
            .pool_id = undefined,
            .group_index = undefined,
            .member_index = undefined,
        };
    }

    pub fn setSlot(self: *Self, slot: IdSlot) !void {
        if (slot.entity_id.idx() < self.slots.items.len) self.slots.items[slot.entity_id.idx()] = slot else try self.slots.append(self.allocator, slot);
    }

    pub fn getSlot(self: *Self, entity_id: Registry.EntityId) IdSlot {
        for (self.queue.items) |queued_entity_id| {
            std.debug.assert(!queued_entity_id.eql(entity_id));
        }
        return self.slots.items[entity_id.idx()];
    }
};
