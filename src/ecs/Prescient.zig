const std = @import("std");
const testing = std.testing;
const PR = @import("PoolRegistry.zig");
const EM = @import("EntityManager.zig");
const PM = @import("PoolManager.zig");
const SM = @import("SystemManager.zig");
const PI = @import("PoolInterface.zig");
const PoolInterface = PI.PoolInterfaceType;
const PoolConfig = PI.PoolConfig;

pub const Prescient = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    entity_manager: EM.EntityManager,
    pool_manager: PM.PoolManager,
    system_manager: SM.SystemManager,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var self: Self = undefined; 
        self.allocator = allocator;

        self.entity_manager = try EM.EntityManager.init(allocator);
        self.pool_manager = PM.PoolManager.init(allocator);
        self.system_manager = SM.SystemManager.init(allocator, &self.pool_manager);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.entity_manager.deinit(); 
        self.pool_manager.deinit();
        self.system_manager.deinit();
    }

    pub fn update(self: *Self) !void {
        try self.system_manager.update();
        self.pool_manager.flushNewAndReallocatingLists();
        self.pool_manager.flushAllPools();
    }

    pub fn getPool(self: *Self, comptime config: PoolConfig) PoolInterface(config) {
        return PoolInterface(config).init(config.name, &self.entity_manager);
    } 


};

test "Basic" {
    var api = try Prescient.init(testing.allocator);    
    defer api.deinit();
    
    var interface = api.getPool(.{.name = .MovementPool, .req = &.{}, .opt = &.{.Position, .Velocity}});
    _ = 
}
