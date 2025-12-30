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

    _allocator: std.mem.Allocator,
    _entity_manager: EM.EntityManager,
    _pool_manager: *PM.PoolManager,
    _system_manager: SM.SystemManager,
    ent: Ent = undefined,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        // Allocate pool_manager on heap so it has a stable address
        const pool_manager = try allocator.create(PM.PoolManager);
        pool_manager.* = PM.PoolManager.init(allocator);

        const entity_manager = try EM.EntityManager.init(allocator);
        const system_manager = SM.SystemManager.init(allocator, pool_manager);

        const self = try allocator.create(Self);
        self.* = .{
            ._allocator = allocator,
            ._entity_manager = entity_manager,
            ._pool_manager = pool_manager,
            ._system_manager = system_manager,
        };

        self.ent = Ent.init(allocator, &self._entity_manager, pool_manager, &self._system_manager);

        return self;
    }

    pub fn deinit(self: *Self) void {
        const allocator = self._allocator;
        self._entity_manager.deinit();
        self._pool_manager.deinit();
        allocator.destroy(self._pool_manager);
        self._system_manager.deinit();
        allocator.destroy(self);
    }

    pub fn update(self: *Self) !void {
        try self._pool_manager.flushAllPools(&self._entity_manager);
        try self._system_manager.update();
        self._pool_manager.flushNewAndReallocatingLists();
    }

    pub fn getPool(self: *Self, comptime pool_name: PR.PoolName) !PoolInterface(pool_name) {
        const pool = try self._pool_manager.getOrCreatePool(pool_name);
        return PoolInterface(pool_name).init(pool, &self._entity_manager);
    } 


    pub fn getSystem(self: *Self, comptime system: SR.SystemName) *SR.getTypeByName(system) {
        return self._system_manager.getSystem(system);
    }
};

pub const Ent = struct {
    const Self = @This();

    _allocator: std.mem.Allocator,
    _entity_manager: *EM.EntityManager,
    _pool_manager: *PM.PoolManager,
    _system_manager: *SM.SystemManager,

    pub fn init(
        allocator: std.mem.Allocator,
        entity_manager: *EM.EntityManager,
        pool_manager: *PM.PoolManager,
        system_manager: *SM.SystemManager,
    ) Self {
        const self = Self{
            ._allocator = allocator,
            ._entity_manager = entity_manager,
            ._pool_manager = pool_manager,
            ._system_manager = system_manager,
        };

        return self;
    }

    pub fn getEntityComponentData(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !*CR.getTypeByName(component) {
        const slot = try self._entity_manager.getSlot(entity);

        // Use inline for with comptime conditional to eliminate dead code paths
        inline for (std.meta.fields(PR.PoolName)) |field| {
            const pool_name: PR.PoolName = @enumFromInt(field.value);

            if (slot.pool_name == pool_name) {
                const pool = try self._pool_manager.getOrCreatePool(pool_name);

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
};

test "Basic" {
    const api = try Prescient.init(testing.allocator);
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

