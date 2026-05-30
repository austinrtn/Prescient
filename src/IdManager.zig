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

    pub fn init(allocator: std.mem.Allocator) Self {
        const self: Self = .{ .allocator = allocator };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.slots.deinit(self.allocator);
        self.queue.deinit(self.allocator);
    }

    pub fn setNextSlot(self: *Self, pool: PR.Enum, arch_idx: u32, ent_idx: u32) !u32{
        const next_queued_slot = self.queue.pop();
        
        if(next_queued_slot) |idx| {
            const slot: *IdSlot = &self.slots.items[idx];
            slot.* = IdSlot{
                .id = slot.id,
                .pool = pool,
                .arch_idx = arch_idx,
                .ent_idx = ent_idx,
            };
            
            return idx;
        }

        const slot_idx: u32 = @intCast(self.slots.items.len);
        const new_slot: IdSlot = .{
            .id = slot_idx,
            .pool = pool,
            .arch_idx = arch_idx,
            .ent_idx = ent_idx,
        };

        try self.slots.append(self.allocator, new_slot);
        return new_slot.id; 
    }
};
