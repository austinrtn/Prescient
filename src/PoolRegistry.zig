const std = @import("std");
const Pools = @import("Registry.zig").Registry.PoolConfigs;
const EntPool = @import("EntPool.zig").EntPool;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;

pub const Config = struct {
    name: []const u8,
    components: []const CR.Enum,
};

pub const PoolRegistry = PoolRegistryT(&Pools);

fn PoolRegistryT(comptime pool_configs: []const Config) type {
    return struct {
        pub const Enum = PoolEnumT(pool_configs);
        pub const Tags = std.meta.tags(Enum);
        pub const Types = PoolTypes(pool_configs);
        pub const Conifg = Config;

        const string_map = stringTypeMap(pool_configs);

        pub fn getConfigByEnum(comptime pool: Enum) Config {
            return string_map.get(@tagName(pool)) orelse unreachable;
        }
    };
}

fn PoolEnumT(comptime pool_configs: []const Config) type {
    var names: [pool_configs.len][]const u8 = undefined;
    var vals:[pool_configs.len]u8 = undefined;

    for(pool_configs, 0..) |desc, i| {
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

fn PoolTypes(comptime pool_configs: []const Config) type {
    var names: [pool_configs.len][]const u8 = undefined;
    var types: [pool_configs.len]type = undefined;
    var attrs: [pool_configs.len]std.builtin.Type.StructField.Attributes = undefined;

    for(pool_configs, 0..) |config, i| {
        names[i] = config.name;
        types[i] = EntPool(config);
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

fn stringTypeMap(comptime pool_configs: []const Config) std.StaticStringMap(Config) {
    const KV = struct{[]const u8, Config};
    var values: [pool_configs.len]KV = undefined;

    for(pool_configs, 0..) |config, i| {
        values[i] = .{config.name, config};
    }

    return std.StaticStringMap(Config).initComptime(values);
}
