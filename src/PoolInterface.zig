const std = @import("std");
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const EntPoolType = @import("EntPool.zig").EntPool;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const IdManager = @import("IdManager.zig").IdManager;
const Registry = @import("Registry.zig").Registry;
const EntityId = Registry.EntityId;

pub fn PoolInterface(comptime pool_config: PR.Config) type {
    const EntPool = EntPoolType(pool_config);
    const pool_mask = CR.getBitmaskOfComponents(pool_config.components);

    return struct {
        const Self = @This();
        pub const PoolComponent = EntPool.PoolComponent;
        pub const PoolTag = PR.getEnumByName(pool_config.name);

        ent_pool: *EntPool,
        id_manager: *IdManager,

        pub fn init(ent_pool: *EntPool, id_manager: *IdManager) Self {
            return .{
                .ent_pool = ent_pool,
                .id_manager = id_manager,
            };
        }

        pub fn createEnt(self: *Self, ent: anytype) !EntityId {
            // Get entity's slot, convert the ent anytype fields into specified component types
            var slot = self.id_manager.getNextSlot();
            inline for(std.meta.fields(@TypeOf(ent))) |field| validateComponent(CR.getEnumByName(field.name));
            const converted_ent = CR.AnomToTypedComponentStruct(ent);
            const new_location = try self.ent_pool.addEnt(converted_ent, slot.entity_id);

            slot.pool_id = PoolTag;
            slot.group_index = new_location.group_index;
            slot.member_index = new_location.member_index;
            
            try self.id_manager.setSlot(slot);
            return slot.entity_id;
        }

        pub fn deleteEnt(self:* Self, entity_id: EntityId) !void {
            const slot = self.id_manager.getSlot(entity_id);
            const swapped_ent_id = self.ent_pool.removeEnt(slot.group_index, slot.member_index);
            
            if(swapped_ent_id) |id| {
                var swapped_ent = self.id_manager.getSlot(id);
                swapped_ent.member_index = slot.member_index;
                try self.id_manager.setSlot(swapped_ent);
            }
            try self.id_manager.sendSlotToQueue(entity_id);
        }

        pub fn getComponent(self: *Self, entity_id: EntityId, comptime component: Component) CR.getCompTypeByEnum(component) {
            const slot = self.id_manager.getSlot(entity_id);
            return self.ent_pool.getComponent(Local(component), slot.group_index, slot.member_index);
        }

        pub fn getComponents(self: *Self, entity_id: EntityId, comptime components: []const Component) CR.GetTypeOfComponents(components, false) {
            const slot = self.id_manager.getSlot(entity_id);
            var comp_build: CR.GetTypeOfComponents(components, false) = undefined;

            inline for(components) |comp| {
                @field(comp_build, @tagName(comp)) = self.ent_pool.getComponent(Local(comp), slot.group_index, slot.member_index);
            }
            return comp_build;
        }

        pub fn setComponent(self: *Self, entity_id: EntityId, comptime component: Component, component_value: anytype) void {
            const slot = self.id_manager.getSlot(entity_id);
            const converted_comp_data = CR.convertAnomToComponent(component_value, @tagName(component));
            
            self.ent_pool.setComponent(Local(component), converted_comp_data, slot.group_index, slot.member_index);
        }

        pub fn setComponents(self: *Self, entity_id: EntityId, component_values: anytype) void {
            const slot = self.id_manager.getSlot(entity_id);

            inline for(std.meta.fields(@TypeOf(component_values))) |field| {
                const comp_tag = comptime std.meta.stringToEnum(PoolComponent, field.name) 
                    orelse @compileError("Component " ++ field.name ++ " not found in ent pool {}." ++ @tagName(EntPool.tag)); 
                    
                const comp_val = @field(component_values, field.name); 
                const comp_value = CR.convertAnomToComponent(comp_val, field.name);
                self.ent_pool.setComponent(comp_tag, comp_value, slot.group_index, slot.member_index);
            }
        }

        pub fn addComponent(self: *Self, entity_id: EntityId, comptime component: Component, component_value: anytype) !void {
            var slot = self.id_manager.getSlot(entity_id);
            const converted_comp_data = CR.convertAnomToComponent(component_value, @tagName(component));
            const res = try self.ent_pool.addComponent(Local(component), converted_comp_data, entity_id, slot.group_index, slot.member_index);

            slot.group_index = res.new_group_index;
            slot.member_index = res.new_member_index;

            if (res.swapped_entity_id) |swapped_entity_id| {
                var swapped_slot = self.id_manager.getSlot(swapped_entity_id);
                swapped_slot.member_index = res.swapped_member_index.?;
                try self.id_manager.setSlot(swapped_slot);
            }

            try self.id_manager.setSlot(slot);
        }
        
        fn validateComponent(comptime component: Component) void {
            comptime {
                if(!CR.maskContainsComponent(component, pool_mask)) {
                    @compileError("Component " ++ @tagName(component) ++ " is not a member of Entity Pool " ++ pool_config.name ++ "\n");
                }
            }
        }

        fn Local(comptime component: Component) PoolComponent {
            return CR.localizeComponent(component, EntPool);
        }
    };
}
