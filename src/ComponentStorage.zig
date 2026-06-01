const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;

pub fn ComponentStorage(comptime components: []const Component) type {
    var names: [components.len][]const u8 = undefined;
    var types: [components.len]type = undefined;
    var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

    for(components, 0..) |comp, i| {
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