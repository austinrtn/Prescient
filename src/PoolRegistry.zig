const std = @import("std");
const PoolDescs = @import("Registry.zig").Registry.PoolDescs;
const EntPool = @import("EntPool.zig").EntPool;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const GlobalComponent = CR.Component;

const StorageStrategy = enum { archetype, sparse_set };

pub const PoolDesc = struct {
    name: []const u8,
    components: []const GlobalComponent,
    storage_strategy: StorageStrategy,
};

pub const PoolRegistry = PoolRegistryT(&PoolDescs);

fn PoolRegistryT(comptime pool_descs: []const PoolDesc) type {
    const PoolEnum = PoolEnumT(pool_descs);

    return struct {
        pub const Enum = PoolEnum;
        pub const Tags = std.meta.tags(Enum);
        pub const Types = PoolTypes(pool_descs, Enum);
        pub const Desc = PoolDesc;

        const desc_enum_map = DescEnumMap(pool_descs);

        pub fn getDescByEnum(comptime pool: Enum) PoolDesc {
            return desc_enum_map.get(@tagName(pool)) orelse unreachable;
        }

        pub fn GetPoolConfig(comptime tag: Enum) type {
            const desc = getDescByEnum(tag);
            return struct {
                pub const Tag = tag;
                pub const Component = ComponentEnumT(desc.components);
                pub const ComponentTags = std.meta.tags(Component);
                pub const global_components = desc.components;
                pub const storage_strategy = desc.storage_strategy;

                pub fn localize(comptime component: GlobalComponent) Component {
                    inline for (ComponentTags) |pool_component| {
                        if (@intFromEnum(pool_component) == @intFromEnum(component)) {
                            return pool_component;
                        }
                    }

                    @compileError("Component " ++ @tagName(component) ++ " does not exist within pool scope!");
                }

                pub fn globalize(comptime pool_component: Component) GlobalComponent {
                    return @enumFromInt(@intFromEnum(pool_component));
                }

                pub fn getComponentFromName(comptime name: []const u8) Component {
                    return std.meta.stringToEnum(Component, name) orelse 
                    @compileError("Component " ++ name ++ " does not exist in pool" ++ @tagName(Tag));
                }
            };
        }
    };
}

fn PoolEnumT(comptime pool_configs: []const PoolDesc) type {
    var names: [pool_configs.len][]const u8 = undefined;
    var vals: [pool_configs.len]u8 = undefined;

    for (pool_configs, 0..) |desc, i| {
        names[i] = desc.name;
        vals[i] = @intCast(i);
    }

    return @Enum(
        u8,
        .exhaustive,
        &names,
        &vals,
    );
}

fn PoolTypes(comptime pool_descs: []const PoolDesc, comptime PoolEnum: type) type {
    var names: [pool_descs.len][]const u8 = undefined;
    var types: [pool_descs.len]type = undefined;
    var attrs: [pool_descs.len]std.builtin.Type.StructField.Attributes = undefined;

    for (pool_descs, 0..) |config, i| {
        names[i] = config.name;
        const tag = std.meta.stringToEnum(PoolEnum, config.name) orelse unreachable;
        types[i] = EntPool(tag);
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

fn ComponentEnumT(comptime components: []const GlobalComponent) type {
    var names: [components.len][]const u8 = undefined;
    var vals: [components.len]u8 = undefined;

    for (components, 0..) |component, i| {
        names[i] = @tagName(component);
        vals[i] = @intFromEnum(component);
    }

    return @Enum(
        u8,
        .exhaustive,
        &names,
        &vals,
    );
}

fn DescEnumMap(comptime pool_descs: []const PoolDesc) std.StaticStringMap(PoolDesc) {
    const KV = struct { []const u8, PoolDesc };
    var values: [pool_descs.len]KV = undefined;

    for (pool_descs, 0..) |config, i| {
        values[i] = .{ config.name, config };
    }

    return std.StaticStringMap(PoolDesc).initComptime(values);
}

test "pool config exposes tag-scoped component metadata" {
    inline for (PoolRegistry.Tags) |tag| {
        const Config = PoolRegistry.GetPoolConfig(tag);
        const Local = Config.localize;
        const Global = Config.globalize;
        try std.testing.expectEqual(tag, Config.Tag);
        try std.testing.expectEqual(Config.global_components.len, Config.ComponentTags.len);

        inline for (Config.global_components) |component| {
            try std.testing.expectEqual(component, Global(Local(component)));
        }
    }
}
