const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;

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
        global_ids: ArrayList(u32) = .empty,
        comp_storage: Storage = undefined,
        count: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{.allocator = allocator};
            inline for(StorageFields) |field| @field(self.comp_storage, field.name) = .empty;
            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(StorageFields) |field| {
                @field(self.comp_storage, field.name).deinit(self.allocator);
            }
            self.global_ids.deinit(self.allocator);
        }

        pub fn append(self: *Self, ent: anytype, global_id: u32) !u32 {
            const EntT = @TypeOf(ent);

            try self.global_ids.append(self.allocator, global_id);

            inline for(std.meta.fields(EntT)) |field| {
                if(@hasField(Storage, field.name)) {
                    const ent_field = @field(ent, field.name);
                    const comp_converted = CR.convertAnomToComponent(ent_field, field.name);
                    try @field(self.comp_storage, field.name).append(self.allocator, comp_converted);
                }
            }

            self.count += 1;
            return @intCast(self.count - 1);
        }

        pub fn remove(self: *Self, ent_index: u32) u32 {
            const idx: usize = @intCast(ent_index);

            const swaped_global_id: u32 = self.global_ids.swapRemove(idx);
            inline for(StorageFields) |field| {
                const comp_list = &@field(self.comp_storage, field.name);
                if(comp_list.items.len > 0) _ = comp_list.swapRemove(idx);
            }

            self.count -= 1;
            return swaped_global_id;
        }

        pub fn getComponent(self: *Self, comptime component: Component, ent_idx: u32) CR.getCompTypeByEnum(component) {
            return @field(self.comp_storage, @tagName(component)).items[ent_idx];
        }

        pub fn getFields(self: *Self) EntTypeSlices {
            var slices: EntTypeSlices = undefined;
            inline for(std.meta.fields(EntTypeSlices)) |field| {
                const list = &@field(self.comp_storage, field.name);
                @field(slices, field.name) = list.items;
            }
            return slices;
        }
    };
}
