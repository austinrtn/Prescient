const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;
const Registry = @import("Registry.zig").Registry;
const EntityId = Registry.EntityId;
const MemberIndex = Registry.MemberIndex;

pub fn Archetype(comptime PoolComponent: type) type {
    const Storage = ComponentStorage(PoolComponent);
    const EntTypeSlices = CR.GetTypeOfComponents(PoolComponent.GlobalComponents, true);
    const bit_mask = CR.getBitmaskOfComponents(PoolComponent.GlobalComponents);

    return struct {
        const Self = @This();

        pub const Components = PoolComponent.Tags;
        pub const mask = bit_mask;
        allocator: std.mem.Allocator,
        entity_ids: ArrayList(EntityId) = .empty,
        member_indices: ArrayList(MemberIndex) = .empty,
        comp_storage: Storage = undefined,
        count: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .comp_storage = Storage.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.comp_storage.deinit();
            self.member_indices.deinit(self.allocator);
            self.entity_ids.deinit(self.allocator);
        }

        pub fn append(self: *Self, ent: anytype, entity_id: EntityId) !MemberIndex {
            const EntType = @TypeOf(ent);
            try self.entity_ids.append(self.allocator, entity_id);

            inline for (comptime PoolComponent.Tags) |comp| {
                const field_name = @tagName(comp);
                if (@hasField(EntType, field_name)) {
                    const comp_value = @field(ent, field_name);
                    try self.comp_storage.appendValueIfPresent(comp, comp_value);
                }
            }

            self.count += 1;
            const memeber_idx: MemberIndex = .init(self.count - 1);
            try self.member_indices.append(self.allocator, memeber_idx);

            return memeber_idx;
        }

        pub fn remove(self: *Self, member_index: MemberIndex) ?EntityId {
            const member_idx = member_index.idx();
            const last_member_idx = self.member_indices.items[self.count - 1];
            const swapped_ent_id = if (!member_index.eql(last_member_idx)) self.entity_ids.items[self.count - 1] else null;

            _ = self.entity_ids.swapRemove(member_idx);
            _ = self.member_indices.swapRemove(member_idx);
            inline for (comptime PoolComponent.Tags) |component| {
                const comp_list = &@field(self.comp_storage.inner_storage, @tagName(component));
                if (comp_list.items.len > 0) _ = comp_list.swapRemove(member_idx);
            }

            self.count -= 1;
            return swapped_ent_id;
        }

        pub fn getComponent(self: *Self, comptime component: PoolComponent.Enum, member_index: MemberIndex) CR.GetComponentTypeByEnum(PoolComponent.globalize(component)) {
            const comp_array = &@field(self.comp_storage.inner_storage, @tagName(component));
            return comp_array.items[member_index.idx()];
        }

        pub fn setComponent(self: *Self, comptime component: PoolComponent.Enum, component_data: CR.GetComponentTypeByEnum(PoolComponent.globalize(component)), member_index: MemberIndex) void {
            const comp_array = &@field(self.comp_storage.inner_storage, @tagName(component));
            comp_array.items[member_index.idx()] = component_data;
        }

        pub fn getFields(self: *Self) EntTypeSlices {
            var slices: EntTypeSlices = undefined;
            inline for (std.meta.fields(EntTypeSlices)) |field| {
                const list = &@field(self.comp_storage.inner_storage, field.name);
                @field(slices, field.name) = list.items;
            }
            return slices;
        }
    };
}
