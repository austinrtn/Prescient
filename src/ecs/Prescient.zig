const std = @import("std");
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const SR = @import("SystemRegistry.zig");
const EM = @import("EntityManager.zig");
const PM = @import("PoolManager.zig");
const SM = @import("SystemManager.zig");
const PI = @import("PoolInterface.zig");
const PoolInterface = PI.PoolInterfaceType;

pub const Prescient = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    entity_manager: EM.EntityManager,
    pool_manager: *PM.PoolManager,
    system_manager: SM.SystemManager,

    pub fn init(allocator: std.mem.Allocator) !Self {
        // Allocate pool_manager on heap so it has a stable address
        const pool_manager = try allocator.create(PM.PoolManager);
        pool_manager.* = PM.PoolManager.init(allocator);

        const self: Self = .{
            .allocator = allocator,
            .entity_manager = try EM.EntityManager.init(allocator),
            .pool_manager = pool_manager,
            .system_manager = SM.SystemManager.init(allocator, pool_manager),
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.entity_manager.deinit();
        self.pool_manager.deinit();
        self.allocator.destroy(self.pool_manager);
        self.system_manager.deinit();
    }

    pub fn update(self: *Self) !void {
        try self.system_manager.update();
        self.pool_manager.flushNewAndReallocatingLists();
        try self.pool_manager.flushAllPools(&self.entity_manager);
    }

    pub fn getPool(self: *Self, comptime pool_name: PR.PoolName) !PoolInterface(pool_name) {
        const pool = try self.pool_manager.getOrCreatePool(pool_name);
        return PoolInterface(pool_name).init(pool, &self.entity_manager);
    } 

    pub fn getEntityComponentData(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !*CR.getTypeByName(component) {
        const slot = try self.entity_manager.getSlot(entity);

        // Use inline for with comptime conditional to eliminate dead code paths
        inline for (std.meta.fields(PR.PoolName)) |field| {
            const pool_name: PR.PoolName = @enumFromInt(field.value);

            if (slot.pool_name == pool_name) {
                const pool = try self.pool_manager.getOrCreatePool(pool_name);

                // Only compile getComponent call if this pool has the component
                if (comptime PR.poolHasComponent(pool_name, component)) {
                    return pool.getComponent(
                        slot.mask_list_index,
                        slot.storage_index,
                        slot.pool_name,
                        component,
                    );
                } else {
                    return error.ComponentNotInPool;
                }
            }
        }

        unreachable;
    }

    pub fn getSystem(self: *Self, comptime system: SR.SystemName) *SR.getTypeByName(system) {
        return self.system_manager.getSystem(system);
    }
};

test "Basic" {
    var api = try Prescient.init(testing.allocator);
    defer api.deinit();

    var interface = try api.getPool(.MovementPool);
    _ = try interface.createEntity(.{
        .Position = .{.x = 3, .y = 5},
        .Velocity = .{.dx = 1, .dy = 0},
    });

    for(0..5) |_| {
        try api.update();
    }

    api.getSystem(.Movement).delta_time = 3;
}

