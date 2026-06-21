const std = @import("std");
const Pools = @import("Registry.zig").Registry.PoolConfigs;
const EntPool = @import("EntPool.zig").EntPool;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const GlobalCompoennt = CR.Component;
const ComponentSubset = @import("ComponentSubset.zig");

const StorageStrategy = enum { archetype, sparse_set };

pub const PoolDesc = struct {
    name: []const u8,
    components: []const GlobalCompoennt,
    storage_strategy: StorageStrategy,
};

pub const PoolRegistry = PoolRegistryT(&Pools);

fn PoolRegistryT(comptime pool_descs: []const PoolDesc) type {
    return struct {
        pub const Enum = PoolEnumT(pool_descs);
        pub const Tags = std.meta.tags(Enum);
        pub const Types = PoolTypes(pool_descs);
        pub const Desc = PoolDesc;

        const desc_enum_map = DescEnumMap(pool_descs);

        pub fn getDescByEnum(comptime pool: Enum) PoolDesc {
            return desc_enum_map.get(@tagName(pool)) orelse unreachable;
        }

        pub fn getEnumByName(comptime name: []const u8) Enum {
            return std.meta.stringToEnum(Enum, name) orelse unreachable;
        }
        
        pub fn GetPoolConfig(comptime tag: Enum) type {
            const desc = getDescByEnum(tag);
            return struct {
                pub const Tag = std.meta.stringToEnum(Enum, desc.name) orelse unreachable;
                pub const Component = ComponentSubset.init(desc.components);
                pub const ComponentTags = std.meta.tags(Component);
                pub const global_components = desc.components;
                pub const storage_strategy = desc.storage_strategy;
                
                pub fn localize(comptime component: Component) Enum {
                    inline for (Tags) |pool_component| { if (@intFromEnum(pool_component) == @intFromEnum(component)) {
                            return pool_component;
                        }
                    }
        
                    @compileError("Component " ++ @tagName(component) ++ " does not exist within pool scope!");
                }

                
                pub fn globalize(comptime pool_component: Enum) Component {
                    return @enumFromInt(@intFromEnum(pool_component));
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

fn PoolTypes(comptime pool_descs: []const PoolDesc) type {
    var names: [pool_descs.len][]const u8 = undefined;
    var types: [pool_descs.len]type = undefined;
    var attrs: [pool_descs.len]std.builtin.Type.StructField.Attributes = undefined;

    for (pool_descs, 0..) |config, i| {
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

fn DescEnumMap(comptime pool_descs: []const PoolDesc) std.StaticStringMap(PoolDesc) {
    const KV = struct { []const u8, PoolDesc};
    var values: [pool_descs.len]KV = undefined;

    for (pool_descs, 0..) |config, i| {
        values[i] = .{ config.name, config };
    }

    return std.StaticStringMap(PoolDesc).initComptime(values);
}