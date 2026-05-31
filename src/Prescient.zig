const std = @import("std");
const Registry = @import("Registry.zig").Registry;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const ComponentRegistry = CR.ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const PoolManager = @import("PoolManager.zig").PoolManager;
const EntPool = @import("EntPool.zig").EntPool;
const IdManager = @import("IdManager.zig").IdManager;

pub const Prescient = struct {
    pub const Self = @This();
    allocator: std.mem.Allocator,

    id_manager: IdManager = undefined,
    pool_manager: PoolManager = undefined,

    pub fn init(allocator: std.mem.Allocator) Self {
        var self: Self = .{.allocator = allocator};
        self.pool_manager = .init(allocator);
        self.id_manager = .init(allocator);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.pool_manager.deinit();
        self.id_manager.deinit();
    }

    pub fn getPool(self: *Self, comptime pool: PR.Enum) *EntPool(PR.getConfigByEnum(pool)) {
        return self.pool_manager.getPool(pool);
    }

    pub fn createEnt(self: *Self, comptime pool: PR.Enum, ent: anytype) !void {
        const ent_pool = self.getPool(pool);

        const next_slot_id = self.id_manager.getNextSlotId();
        const idx = try ent_pool.append(ent, next_slot_id);
        self.id_manager.setNextSlot(pool, idx.arch_idx, idx.ent_idx);
    }
};
