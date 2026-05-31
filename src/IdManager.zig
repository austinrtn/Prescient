const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;

pub const IdSlot = struct {
    id: u32,
    pool: PR.Enum,
    arch_idx: u32,
    ent_idx: u32,
};

pub const IdManager = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    slots: ArrayList(IdSlot) = .empty,
    queue: ArrayList(u32) = .empty,
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
        if(self.queue.pop()) |idx| return self.slots.items[idx];

        const id: u32 = @intCast(self.slots.items.len);
        return .{
            .id = id,
            .pool = undefined,
            .arch_idx = undefined,
            .ent_idx = undefined,
        };
    }

    pub fn setSlot(self: *Self, slot: IdSlot) !void {
        if(slot.id < self.slots.items.len) self.slots.items[slot.id] = slot
        else try self.slots.append(self.allocator, slot);
    }

    pub fn getSlot(self: *Self, id: u32) IdSlot {
        std.debug.assert(std.mem.findScalar(u32, self.queue.items, id) == null);
        return self.slots.items[id];
    }
};
