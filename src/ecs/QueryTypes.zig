const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("../registries/ComponentRegistry.zig");
const PR = @import("../registries/PoolRegistry.zig");
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const StructField = std.builtin.Type.StructField;
const Entity = @import("EntityManager.zig").Entity;

// Determines how a pool's archetypes are accessed during query iteration
pub const ArchetypeAccess = enum{
    // All archetypes in the pool are guaranteed to match the query (all query components are required)
    Direct,
    // Archetypes must be individually checked since some query components are optional
    Lookup,
};

pub fn ArchetypeCacheType(comptime components: []const CR.ComponentName) type {
    // +1 for the entities field
    var fields: [components.len + 1]StructField = undefined;

    // First field: entities slice
    fields[0] = StructField{
        .name = "entities",
        .type = []Entity,
        .alignment = @alignOf([]Entity),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field: CompName: []Component (direct slices for unified archetype/sparse API)
    for(components, 1..) |comp, i| {
        const name = @tagName(comp);
        const T = []CR.getTypeByName(comp);
        fields[i] = StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .fields = &fields,
            .layout = .auto,
            .is_tuple = false,
            .backing_integer = null,
            .decls = &.{},
        }
    });
}

/// PoolElementType - One type PER pool with comptime constants
/// This allows Query to access pool info at comptime without inline switch
pub fn PoolElementType(comptime pool_name: PR.PoolName, comptime components: []const CR.ComponentName) type {
    return struct {
        pub const POOL_NAME = pool_name;
        pub const STORAGE_STRATEGY = PR.getPoolFromName(pool_name).storage_strategy;

        access: ArchetypeAccess,
        archetype_indices: ArrayList(usize),
        archetype_cache: ArrayList(ArchetypeCacheType(components)),
        sparse_cache: ArrayList(usize),
    };
}

pub fn countMatchingPools(comptime components: []const CR.ComponentName) comptime_int {
    var count: comptime_int = 0;

    for(PR.pool_types) |pool_type| {
        var query_match = true;
        var req_match = true;

        for(components) |component| {
            const component_bit = MaskManager.Comptime.componentToBit(component);
            const in_pool = MaskManager.maskContains(pool_type.pool_mask, component_bit);

            if(!in_pool) {
                query_match = false;
                req_match = false;
                break;
            }

            if(req_match) {
                const contained_in_req = MaskManager.maskContains(pool_type.REQ_MASK, component_bit);
                if(!contained_in_req) {
                    req_match = false;
                }
            }
        }

        if(req_match or query_match) {
            count += 1;
        }
    }
    return count;
}

/// Match result struct for pool lookup
const PoolMatch = struct {
    pool_name: PR.PoolName,
    access: ArchetypeAccess,
};

/// Returns array of matching pool names with their access types
fn findMatchingPools(comptime components: []const CR.ComponentName) [countMatchingPools(components)]PoolMatch {
    const count = countMatchingPools(components);
    var matches: [count]PoolMatch = undefined;
    var idx: usize = 0;

    for(PR.pool_types, 0..) |pool_type, i| {
        var query_match = true;
        var req_match = true;

        for(components) |component| {
            const component_bit = MaskManager.Comptime.componentToBit(component);
            const in_pool = MaskManager.maskContains(pool_type.pool_mask, component_bit);

            if(!in_pool) {
                query_match = false;
                req_match = false;
                break;
            }

            if(req_match) {
                const contained_in_req = MaskManager.maskContains(pool_type.REQ_MASK, component_bit);
                if(!contained_in_req) {
                    req_match = false;
                }
            }
        }

        if(req_match or query_match) {
            matches[idx] = .{
                .pool_name = @enumFromInt(i),
                .access = if(req_match) .Direct else .Lookup,
            };
            idx += 1;
        }
    }
    return matches;
}

/// Generates a heterogeneous struct type with one field per matching pool.
/// Each field has its own PoolElementType with comptime POOL_NAME.
pub fn PoolElementsType(comptime components: []const CR.ComponentName) type {
    const matches = comptime findMatchingPools(components);
    var fields: [matches.len]StructField = undefined;

    for(matches, 0..) |match, i| {
        const ElemType = PoolElementType(match.pool_name, components);
        fields[i] = StructField{
            .name = @tagName(match.pool_name),
            .type = ElemType,
            .alignment = @alignOf(ElemType),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .fields = &fields,
            .layout = .auto,
            .is_tuple = false,
            .backing_integer = null,
            .decls = &.{},
        }
    });
}

/// Returns an initialized PoolElementsType instance with access modes set
pub fn findPoolElements(comptime components: []const CR.ComponentName) PoolElementsType(components) {
    const matches = comptime findMatchingPools(components);
    var result: PoolElementsType(components) = undefined;

    inline for(matches) |match| {
        const field_name = @tagName(match.pool_name);
        @field(result, field_name) = .{
            .access = match.access,
            .archetype_indices = .{},
            .archetype_cache = .{},
            .sparse_cache = .{},
        };
    }

    return result;
}
