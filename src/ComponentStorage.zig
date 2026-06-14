const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;

fn InnerComponentStorage(comptime components: []const Component) type {
    var names: [components.len][]const u8 = undefined;
    var types: [components.len]type = undefined;
    var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

    for (components, 0..) |comp, i| {
        const T = CR.getCompTypeByEnum(comp);
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

pub fn ComponentStorage(comptime components: []const Component) type {
    const InnerStorage = InnerComponentStorage(components);

    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        inner_storage: InnerStorage = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{ .allocator = allocator };

            inline for (std.meta.fields(InnerStorage)) |field| {
                @field(self.inner_storage, field.name) = .empty;
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for (std.meta.fields(InnerStorage)) |field| {
                @field(self.inner_storage, field.name).deinit(self.allocator);
            }
        }

        pub fn getComponentArray(self: *Self, comptime component: Component) *ArrayList(CR.getCompTypeByEnum(component)) {
            return &@field(self.inner_storage, @tagName(component));
        }
    };
}
