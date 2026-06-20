const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;

fn InnerComponentStorage(comptime PoolComponent: type) type {
    var names: [PoolComponent.Tags.len][]const u8 = undefined;
    var types: [PoolComponent.Tags.len]type = undefined;
    var attrs: [PoolComponent.Tags.len]std.builtin.Type.StructField.Attributes = undefined;

    for (PoolComponent.Tags, 0..) |component, i| {
        const T = CR.GetComponentTypeByEnum(PoolComponent.globalize(component));
        names[i] = @tagName(component);
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

/// Component Storage 
pub fn ComponentStorage(comptime PoolComponent: type) type {
    const InnerStorage = InnerComponentStorage(PoolComponent);

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

        pub fn append(self: *Self, comptime component: PoolComponent.Enum, component_value: CR.GetComponentTypeByEnum(PoolComponent.Globalize(component))) !void {
            try @field(self.inner_storage, @tagName(component)).append(self.allocator, component_value);
        } 

        pub fn appendValueIfPresent(self: *Self, comptime component: PoolComponent.Enum, component_value: anytype) !void {
            const comp_info = @typeInfo(@TypeOf(component_value));
            const field_name = comptime @tagName(component);
            
            if (comp_info == .optional and component_value != null) {
                try @field(self.inner_storage, field_name).append(self.allocator, component_value.?);
            } else if (comp_info != .optional) {
                try @field(self.inner_storage, field_name).append(self.allocator, component_value);
            }
        }

        pub fn deinit(self: *Self) void {
            inline for (std.meta.fields(InnerStorage)) |field| {
                @field(self.inner_storage, field.name).deinit(self.allocator);
            }
        }

        pub fn getComponentArray(self: *Self, comptime component: PoolComponent.Enum) *ArrayList(CR.GetComponentTypeByEnum(PoolComponent.globalize(component))) {
            return &@field(self.inner_storage, @tagName(component));
        }
    };
}
