const std = @import("std");
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Component;

pub fn init(comptime components: []const Component) type {
    var names: [components.len][]const u8 = undefined;
    var vals: [components.len]u8 = undefined;

    for (components, 0..) |comp, i| {
        names[i] = @tagName(comp);
        vals[i] = @intFromEnum(comp);
    }

    return @Enum(
        u8,
        .exhaustive,
        &names,
        &vals,
    );
}
