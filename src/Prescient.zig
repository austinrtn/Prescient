const std = @import("std");
const Registry = @import("Registry.zig").Registry;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const PoolManager = @import("PoolManager.zig").PoolManager;
const PoolInterface = @import("PoolInterface.zig").PoolInterface;
const IdManager = @import("IdManager.zig").IdManager;
const EntityId = Registry.EntityId;

pub const Prescient = struct {
    pub const Self = @This();
    allocator: std.mem.Allocator,

    id_manager: *IdManager = undefined,
    pool_manager: *PoolManager = undefined,
    ent: EntNamespace = undefined,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Prescient);
        self.* = .{ .allocator = allocator };

        self.pool_manager = try allocator.create(PoolManager);
        self.pool_manager.* = .init(allocator);

        self.id_manager = try allocator.create(IdManager);
        self.id_manager.* = .init(allocator);

        self.ent = .{ .prescient = self };
        return self;
    }

    pub fn deinit(self: *Self) void {
        const allocator = self.allocator;

        self.pool_manager.deinit();
        self.id_manager.deinit();
        allocator.destroy(self.pool_manager);
        allocator.destroy(self.id_manager);
        allocator.destroy(self);
    }

    pub fn getPool(self: *Self, comptime pool: PR.Enum) PoolInterface(PR.getConfigByEnum(pool)) {
        const ent_pool = self.pool_manager.getPool(pool);
        return PoolInterface(PR.getConfigByEnum(pool)).init(ent_pool, self.id_manager);
    }
};

const EntNamespace = struct {
    pub const Self = @This();
    prescient: *Prescient,

    pub fn create(self: *Self, comptime pool: PR.Enum, ent: anytype) !EntityId {
        const ent_pool = self.prescient.pool_manager.getPool(pool);
        var pool_interface = PoolInterface(PR.getConfigByEnum(pool)).init(ent_pool, self.prescient.id_manager);
        return try pool_interface.createEnt(ent);
    }

    pub fn getComponent(self: *Self, entity_id: EntityId, comptime component: Component) CR.GetComponentTypeByEnum(component) {
        const slot = self.prescient.id_manager.getSlot(entity_id);

        switch (slot.pool_id) {
            inline else => |p| {
                var pool_interface = self.prescient.getPool(p);
                return pool_interface.getComponent(entity_id, component);
            },
        }
    }
};
