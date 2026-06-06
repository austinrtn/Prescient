const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;
const Registry = @import("Registry.zig").Registry;

pub fn Archetype(comptime components: []const Component) type {
    const Storage = ComponentStorage(components);
    const StorageFields = std.meta.fields(Storage);
    const EntTypeSlices = CR.GetTypeOfComponents(components, true);
    const bit_mask = CR.getBitmaskOfComponents(components);

    return struct {
        const Self = @This();

        pub const Components = components;
        pub const mask = bit_mask;
        allocator: std.mem.Allocator,
        entity_ids: ArrayList(Registry.EntityId) = .empty,
        member_indices: ArrayList(Registry.MemberIndex) = .empty,
        comp_storage: Storage = undefined,
        count: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{ .allocator = allocator };
            inline for (StorageFields) |field| @field(self.comp_storage, field.name) = .empty;
            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for (StorageFields) |field| {
                @field(self.comp_storage, field.name).deinit(self.allocator);
            }
            self.member_indices.deinit(self.allocator);
            self.entity_ids.deinit(self.allocator);
        }

        pub fn append(self: *Self, ent: anytype, entity_id: Registry.EntityId) !Registry.MemberIndex {
            const EntT = @TypeOf(ent);

            try self.entity_ids.append(self.allocator, entity_id);

            inline for (std.meta.fields(EntT)) |field| {
                if (@hasField(Storage, field.name)) {
                    const ent_field = @field(ent, field.name);
                    const comp_converted = CR.convertAnomToComponent(ent_field, field.name);
                    try @field(self.comp_storage, field.name).append(self.allocator, comp_converted);
                }
            }

            self.count += 1;
            const memeber_idx: Registry.MemberIndex = .init(self.count - 1);
            try self.member_indices.append(self.allocator, memeber_idx);
            
            return memeber_idx;
        }

        pub fn remove(self: *Self, member_index: Registry.MemberIndex) ?Registry.EntityId {
            const member_idx = member_index.idx();
            const last_member_idx = self.member_indices.items[self.count - 1];
            const swapped_ent_id = if(!member_index.eql(last_member_idx)) self.entity_ids.items[self.count - 1] else null;

            _ = self.entity_ids.swapRemove(member_idx);
            _ = self.member_indices.swapRemove(member_idx);
            inline for (StorageFields) |field| {
                const comp_list = &@field(self.comp_storage, field.name);
                if (comp_list.items.len > 0) _ = comp_list.swapRemove(member_idx);
            }

            self.count -= 1;
            return swapped_ent_id;
        }

        pub fn getComponent(self: *Self, comptime component: Component, member_index: Registry.MemberIndex) CR.getCompTypeByEnum(component) {
            return @field(self.comp_storage, @tagName(component)).items[member_index.idx()];
        }

        pub fn getFields(self: *Self) EntTypeSlices {
            var slices: EntTypeSlices = undefined;
            inline for (std.meta.fields(EntTypeSlices)) |field| {
                const list = &@field(self.comp_storage, field.name);
                @field(slices, field.name) = list.items;
            }
            return slices;
        }
    };
}
