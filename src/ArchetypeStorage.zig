const std = @import("std");
const ArrayList = std.ArrayList;
const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = ComponentRegistry.Enum;

pub fn Archetype(comptime components: []const Component) type {
    const CompFields = compsToArrayList(components);
    const CompStructFields = std.meta.fields(CompFields);
    const EntTypeSlices = ComponentRegistry.GetTypeOfComponents(components, true);
    const bit_mask = ComponentRegistry.getBitmaskOfComponents(components);

    return struct {
        const Self = @This();

        pub const Components = components;
        pub const mask = bit_mask;
        allocator: std.mem.Allocator,
        storage: CompFields = undefined,
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
        }

        pub fn append(self: *Self, ent: anytype) !void {
            const EntT = @TypeOf(ent);

            inline for(std.meta.fields(EntT)) |field| {
                if(@hasField(CompFields, field.name)) {
                    const ent_field = @field(ent, field.name);
                    try @field(self.storage, field.name).append(self.allocator, ent_field);
                }
            }
            self.len += 1;
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

fn compsToArrayList(comptime components: []const Component) type {
    var names: [components.len][]const u8 = undefined;
    var types: [components.len]type = undefined;
    var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

    for(components, 0..) |comp, i| {
        const T = ComponentRegistry.GetTypeByField(comp);
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
