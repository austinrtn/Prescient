const std = @import("std");
const Registry = @import("Registry.zig").Registry;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const PoolManager = @import("PoolManager.zig").PoolManager;
const PoolInterface = @import("PoolInterface.zig").PoolInterface;
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

    pub fn getPool(self: *Self, comptime pool: PR.Enum) PoolInterface(pool){
        const ent_pool = self.pool_manager.getPool(pool);
        return PoolInterface(pool).init(ent_pool, &self.id_manager);
    }

    pub fn getComponent(self: *Self, comptime component: Component, ent_id: u32) CR.getCompTypeByEnum(component) {
        const slot = self.id_manager.getSlot(ent_id);
        
        switch(slot.pool) {
            inline else => |p| {
                var pool_interface = self.getPool(p);
                return pool_interface.getComponent(component, ent_id);
            }
        }
    }
};
