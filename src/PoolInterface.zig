const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const EntPoolType = @import("EntPool.zig").EntPool;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const IdManager = @import("IdManager.zig").IdManager;
const Registry = @import("Registry.zig").Registry;

pub fn PoolInterface(comptime pool_config: PR.Config) type {
    const EntPool = EntPoolType(pool_config);

    return struct {
        const Self = @This();
        const PoolTag = PR.getEnumByName(pool_config.name);

        ent_pool: *EntPool,
        id_manager: *IdManager,

        pub fn init(ent_pool: *EntPool, id_manager: *IdManager) Self {
            return .{
                .ent_pool = ent_pool,
                .id_manager = id_manager,
            };
        }

        pub fn createEnt(self: *Self, ent: anytype) !Registry.EntityId {
            var slot = self.id_manager.getNextSlot();
            const new_location = try self.ent_pool.addEnt(ent, slot.entity_id);

            slot.pool_id = PoolTag;
            slot.group_index = new_location.group_index;
            slot.member_index = new_location.member_index;

            try self.id_manager.setSlot(slot);
            return slot.entity_id;
        }

        pub fn deleteEnt(self:* Self, entity_id: Registry.EntityId) void {
            const slot = self.id_manager.getSlot(entity_id);
            self.ent_pool.remove(slot.group_index, slot.member_index);
        }

        pub fn getComponent(self: *Self, comptime component: Component, entity_id: Registry.EntityId) CR.getCompTypeByEnum(component) {
            const slot = self.id_manager.getSlot(entity_id);
            return self.ent_pool.getComponent(component, slot.group_index, slot.member_index);
        }

        pub fn addComponent(self: *Self, comptime component: Component, comp_data: anytype, entity_id: Registry.EntityId) !void {
            var slot = self.id_manager.getSlot(entity_id);
            const converted_comp_data = CR.convertAnomToComponent(comp_data, @tagName(component));
            if(pool_config.storage_strategy == .sparse_set) {
                const res = try self.ent_pool.addComponent(component, converted_comp_data, slot.group_index, slot.member_index);
    
                slot.group_index = res.new_group_index;
                slot.member_index = res.new_member_index;
    
                if (res.swapped_entity_id) |swapped_entity_id| {
                    var swapped_slot = self.id_manager.getSlot(swapped_entity_id);
                    swapped_slot.member_index = res.swapped_member_index.?;
                    try self.id_manager.setSlot(swapped_slot);
                }
    
                try self.id_manager.setSlot(slot);
            }

            else {
                try self.ent_pool.addComponent(component, converted_comp_data, slot.group_index, slot.member_index);
            }
        }
    };
}
