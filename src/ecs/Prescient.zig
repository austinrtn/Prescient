const std = @import("std");
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const SR = @import("SystemRegistry.zig");
const EM = @import("EntityManager.zig");
const PM = @import("PoolManager.zig");
const SM = @import("SystemManager.zig");
const PI = @import("PoolInterface.zig");
const Query = @import("Query.zig").QueryType;
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
        try self.pool_manager.flushAllPools(&self.entity_manager);
        try self.system_manager.update();
        self.pool_manager.flushNewAndReallocatingLists();
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

    pub fn getQuery(self: *Self, comptime components: []const CR.ComponentName) Query(components) {
        return Query(components).init(self.allocator, self.pool_manager);
    }
};


test "Basic" {
    var api = try Prescient.init(testing.allocator);
    defer api.deinit();

    var pool = try api.getPool(.GeneralPool);
    var ents: [100]EM.Entity = undefined; 
    for(0..ents.len) |i| {
        const new_ent = try pool.createEntity(.{
            .Position = .{.x = 0, .y = 5},
        });
        ents[i] = new_ent;
    }

    try api.update();

    var i: usize = 0;
    for(ents) |ent| {
        try pool.addComponent(ent, .Velocity, .{.dx = 1, .dy = 0});
        i += 1;
        if(i > ents.len - 10) break;
    }
    try api.update();
}

