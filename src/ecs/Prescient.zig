const std = @import("std");
const CR = @import("../registries/ComponentRegistry.zig");
const PR = @import("../registries/PoolRegistry.zig");
const SR = @import("../registries/SystemRegistry.zig");
const EM = @import("EntityManager.zig");
const PM = @import("PoolManager.zig");
const SM = @import("SystemManager.zig");
const PI = @import("PoolInterface.zig");
const Query = @import("Query.zig").QueryType;
const PoolInterface = PI.PoolInterfaceType;

pub fn Prescient(comptime systems: []const SR.SystemName) type {
    return struct {
        pub const Entity = EM.Entity;
        pub const compTypes = CR.compTypes;
        pub const comps = CR.ComponentName;

        const Self = @This();
        var _Prescient: *Self = undefined;
        var _initiated: bool = false;

        pub fn getPrescient() !*Self {
            if(!_initiated) return error.PrescientNotInitiated;
            return _Prescient;
        }

        _allocator: std.mem.Allocator,
        _entity_manager: EM.EntityManager,
        _pool_manager: *PM.PoolManager,
        _system_manager: SM.SystemManager(systems),
        ent: Ent(systems) = undefined,

        pub fn init(allocator: std.mem.Allocator) !*Self {
            // Allocate pool_manager on heap so it has a stable address
            const pool_manager = try allocator.create(PM.PoolManager);
            pool_manager.* = PM.PoolManager.init(allocator);

            const entity_manager = try EM.EntityManager.init(allocator);
            const system_manager = try SM.SystemManager(systems).init(allocator, pool_manager);

            const self = try allocator.create(Self);
            self.* = .{
                ._allocator = allocator,
                ._entity_manager = entity_manager,
                ._pool_manager = pool_manager,
                ._system_manager = system_manager,
            };
            self.ent = Ent(systems).init(allocator, &self._entity_manager, pool_manager, &self._system_manager);

            _initiated = true;
            _Prescient = self;

            try self._system_manager.initializeSystems();

            return self;
        }

        pub fn deinit(self: *Self) void {
            const allocator = self._allocator;
            self._system_manager.deinitializeSystems();
            self._system_manager.deinit();
            self._entity_manager.deinit();
            self._pool_manager.deinit();
            allocator.destroy(self._pool_manager);
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

        pub fn setSystemActive(self: *Self, comptime system: SR.SystemName, active: bool) void {
            self._system_manager.setSystemActive(system, active);
        }

        pub fn isSystemActive(self: *Self, comptime system: SR.SystemName) bool {
            return self._system_manager.isSystemActive(system);
        }

        pub fn getQuery(self: *Self, comptime components: []const CR.ComponentName) !Query(components) {
            return Query(components).init(self._allocator, self._pool_manager);
        }

        pub fn queryPool(self: *Self, comptime pool: PR.PoolName) !Query(PR.getPoolFromName(pool).COMPONENTS) {
            return Query(PR.getPoolFromName(pool).COMPONENTS).init(self._allocator, self._pool_manager);
        }
    };
}

pub fn Ent(comptime systems: []const SR.SystemName) type {
    return struct {
        const Self = @This();

        _allocator: std.mem.Allocator,
        _entity_manager: *EM.EntityManager,
        _pool_manager: *PM.PoolManager,
        _system_manager: *SM.SystemManager(systems),

        pub fn init(
            allocator: std.mem.Allocator,
            entity_manager: *EM.EntityManager,
            pool_manager: *PM.PoolManager,
            system_manager: *SM.SystemManager(systems),
        ) Self {
            const self = Self{
                ._allocator = allocator,
                ._entity_manager = entity_manager,
                ._pool_manager = pool_manager,
                ._system_manager = system_manager,
            };

            return self;
        }

        pub fn add(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void {
            return self.handleFunctionCall(entity, data, struct {

                pub fn run(namespace: *Self, ent: EM.Entity, comptime pool_name: PR.PoolName, value: anytype) !void {
                    const pool = try namespace._pool_manager.getOrCreatePool(pool_name);
                    var pool_interface = pool.getInterface(namespace._entity_manager);
                    if(comptime PR.poolHasComponent(pool_name, component))
                        try pool_interface.addComponent(ent, component, value);
                }
            });
        }

        pub fn remove(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !void {
            return self.handleFunctionCall(entity, null, struct {

                pub fn run(namespace: *Self, ent: EM.Entity, comptime pool_name: PR.PoolName, data: anytype) !void {
                    _ = data;
                    const pool = try namespace._pool_manager.getOrCreatePool(pool_name);
                    var pool_interface = pool.getInterface(namespace._entity_manager);
                    if(comptime PR.poolHasComponent(pool_name, component))
                        try pool_interface.removeComponent(ent, component);
                }
            });
        }

        pub fn destroy(self: *Self, entity: EM.Entity) !void {
            return self.handleFunctionCall(entity, null, struct {

                pub fn run(namespace: *Self, ent: EM.Entity, comptime pool_name: PR.PoolName, data: anytype) !void {
                    _ = data;
                    const pool = try namespace._pool_manager.getOrCreatePool(pool_name);
                    var pool_interface = pool.getInterface(namespace._entity_manager);
                    try pool_interface.destroyEntity(ent);
                }
            });
        }

        pub fn hasComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !bool {
            const slot = try self._entity_manager.getSlot(entity);

            inline for (std.meta.fields(PR.PoolName)) |field| {
                const pool_name: PR.PoolName = @enumFromInt(field.value);

                if (slot.pool_name == pool_name) {
                    const pool = try self._pool_manager.getOrCreatePool(pool_name);
                    var pool_interface = pool.getInterface(self._entity_manager);

                    if (comptime PR.poolHasComponent(pool_name, component)) {
                        return try pool_interface.hasComponent(entity, component);
                    } else {
                        return false;
                    }
                }
            }

            unreachable;
        }

        pub fn getEntityComponentData(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !*CR.getTypeByName(component) {
            const slot = try self._entity_manager.getSlot(entity);

            inline for (std.meta.fields(PR.PoolName)) |field| {
                const pool_name: PR.PoolName = @enumFromInt(field.value);

                if (slot.pool_name == pool_name) {
                    const pool = try self._pool_manager.getOrCreatePool(pool_name);
                    var pool_interface = pool.getInterface(self._entity_manager);

                    if (comptime PR.poolHasComponent(pool_name, component)) {
                        return try pool_interface.getComponent(entity, component);
                    }             
                }
            }

            unreachable;
        }

        fn handleFunctionCall(self: *Self, entity: EM.Entity, data: anytype, func: anytype) !void {
            const slot = try self._entity_manager.getSlot(entity);

            inline for (std.meta.fields(PR.PoolName)) |field| {
                const pool_name: PR.PoolName = @enumFromInt(field.value);

                if (slot.pool_name == pool_name) {
                    try func.run(self, entity, pool_name, data);
                    return;
                }
            }
            unreachable;
        }
    };
}

