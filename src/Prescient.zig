const std = @import("std");
const Registry = @import("Registry.zig").Registry;
const CR = @import("ComponentRegistry.zig");
const ComponentRegistry = CR.ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const PoolManager = @import("PoolManager.zig").PoolManager;

pub const Prescient = struct {
    pub const Self = @This();
    allocator: std.mem.Allocator,
    pool_manager: PoolManager = undefined,

    pub fn init(allocator: std.mem.Allocator) Self {
        var self: Self = .{.allocator = allocator};
        self.pool_manager = .init(allocator);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.pool_manager.deinit();
    }

    pub fn getPool(self: *Self, comptime pool: PR.Enum) *PR.getTypeByEnum(pool) {
        return self.pool_manager.getPool(pool);
    }
};
