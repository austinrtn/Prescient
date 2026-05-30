const std = @import("std");
const ArrayList = std.ArrayList;
const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = ComponentRegistry.Enum;

pub fn Archetype(comptime components: []const Component) type {
    const Storage = getStorageType(components);
    const StorageFields = std.meta.fields(Storage);
    const CompStructFields = std.meta.fields(Storage);
    const EntTypeSlices = ComponentRegistry.GetTypeOfComponents(components, true);
    const bit_mask = ComponentRegistry.getBitmaskOfComponents(components);

    return struct {
        const Self = @This();

        pub const Components = components;
        pub const mask = bit_mask;
        allocator: std.mem.Allocator,
        global_ids: ArrayList(u32) = .empty,
        storage: Storage = undefined,
        len: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{.allocator = allocator};
            inline for(CompStructFields) |field| @field(self.storage, field.name) = .empty;

            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(CompStructFields) |field| {
                @field(self.storage, field.name).deinit(self.allocator);
            }
            self.global_ids.deinit(self.allocator);
        }

        pub fn append(self: *Self, ent: anytype, global_id: u32) !void {
            const EntT = @TypeOf(ent);

            try self.global_ids.append(self.allocator, global_id);
            inline for(std.meta.fields(EntT)) |field| {
                if(@hasField(Storage, field.name)) {
                    const ent_field = @field(ent, field.name);
                    const comp_converted = ComponentRegistry.convertAnomToComponent(ent_field, field.name);
                    try @field(self.storage, field.name).append(self.allocator, comp_converted);
                }
            }
            
            self.len += 1;
        }

        pub fn remove(self: *Self, ent_index: u32) u32 {
            const idx: usize = @intCast(ent_index);

            const swaped_global_id: u32 = self.global_ids.swapRemove(idx);
            inline for(StorageFields) |field| {
                const comp_list = &@field(self.storage, field.name);
                if(comp_list.items.len > 0) _ = comp_list.swapRemove(idx);
            }

            return swaped_global_id;
        }

        pub fn getFields(self: *Self) EntTypeSlices {
            var slices: EntTypeSlices = undefined;
            inline for(std.meta.fields(EntTypeSlices)) |field| {
                const list = &@field(self.storage, field.name);
                @field(slices, field.name) = list.items;
            }
            return slices;
        }
    };
}

fn getStorageType(comptime components: []const Component) type {
    var names: [components.len][]const u8 = undefined;
    var types: [components.len]type = undefined;
    var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

    for(components, 0..) |comp, i| {
        const T = ComponentRegistry.getCompTypeByEnum(comp);
        names[i] = @tagName(comp);
        types[i] = ArrayList(T);
        attrs[i] = .{};
    }

    return @Struct(
        .auto,
        null,
        &names,
        &types,
        &attrs,
    );
}
