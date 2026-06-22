const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;

fn InnerComponentStorage(comptime TAG: PR.Enum) type {
    const Config = PR.GetPoolConfig(TAG);
    const Global = Config.globalize;
    var names: [Config.ComponentTags.len][]const u8 = undefined;
    var types: [Config.ComponentTags.len]type = undefined;
    var attrs: [Config.ComponentTags.len]std.builtin.Type.StructField.Attributes = undefined;

    for (Config.ComponentTags, 0..) |component, i| {
        const T = CR.GetComponentTypeByEnum(Global(component));
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
pub fn ComponentStorage(comptime TAG: PR.Enum) type {
    const Config = PR.GetPoolConfig(TAG);
    const PoolComponent = Config.Component;
    const Global = Config.globalize;
    const InnerStorage = InnerComponentStorage(TAG);

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

        pub fn append(self: *Self, comptime component: PoolComponent, component_value: CR.GetComponentTypeByEnum(Global(component))) !void {
            try @field(self.inner_storage, @tagName(component)).append(self.allocator, component_value);
        }

        pub fn appendValueIfPresent(self: *Self, comptime component: PoolComponent, component_value: anytype) !void {
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

        pub fn getComponentArray(self: *Self, comptime component: PoolComponent) *ArrayList(CR.GetComponentTypeByEnum(Global(component))) {
            return &@field(self.inner_storage, @tagName(component));
        }
    };
}
