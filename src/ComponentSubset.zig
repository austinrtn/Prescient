const std = @import("std");
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;

const Component = CR.Enum;

pub fn ComponentSubset(comptime pool: PR.Enum) type {
    const components = PR.getConfigByEnum(pool).components;

    return struct {
        pub const Enum = CreateComponentSubset(components);
        pub const Tags = std.meta.tags(Enum);

        pub fn localize(comptime component: Component) Enum {
            return std.meta.stringToEnum(Enum, @tagName(component)) orelse
                @compileError("Component " ++ @tagName(component) ++ " does not exist within pool scope!");
        }

        pub fn globalize(comptime pool_component: Enum) Component {
            return std.meta.stringToEnum(Component, @tagName(pool_component)) orelse
                @compileError("Component " ++ @tagName(pool_component) ++ " does not exist within component registry!");
        }
    };
}

fn CreateComponentSubset(comptime components: []const Component) type {
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
