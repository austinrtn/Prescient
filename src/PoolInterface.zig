const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const EntPoolType = @import("EntPool.zig").EntPool;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const IdManager = @import("IdManager.zig").IdManager;

pub fn PoolInterface(pool: PR.Enum) type {
    const pool_config = PR.getConfigByEnum(pool);
    const EntPool = EntPoolType(pool_config);
    return struct {
        const Self = @This();
        const PoolTag = PR.getEnumByName(pool_config.name);
        
        ent_pool: *EntPool,
        id_manager: *IdManager,

        pub fn init(ent_pool: *EntPool, id_manager: *IdManager) Self{
            return .{
                .ent_pool = ent_pool,
                .id_manager = id_manager,
            };
        }
    
        pub fn createEnt(self: *Self, ent: anytype) !u32 {
            var slot = self.id_manager.getNextSlot();
            const new_idx = try self.ent_pool.addEnt(ent, slot.id);
            
            slot.pool = PoolTag;
            slot.arch_idx = new_idx.arch_idx;
            slot.ent_idx = new_idx.ent_idx;

            try self.id_manager.setSlot(slot);
            return slot.id;
        } 

        pub fn getComponent(self: *Self, comptime component: Component, ent_id: u32) CR.getCompTypeByEnum(component) {
            const slot = self.id_manager.getSlot(ent_id);
            return self.ent_pool.getComponent(component, slot.arch_idx, slot.ent_idx);
        }
    };
}
