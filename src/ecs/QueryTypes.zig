const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const StructField = std.builtin.Type.StructField;

// Determines how a pool's archetypes are accessed during query iteration
pub const ArchetypeAccess = enum{
    // All archetypes in the pool are guaranteed to match the query (all query components are required)
    Direct,
    // Archetypes must be individually checked since some query components are optional
    Lookup,
};

pub fn ArchetypeCacheType(comptime components: []const CR.ComponentName) type {
    var fields: [components.len]StructField = undefined;
    //~Field: CompName: []Component
    for(components, 0..) |comp, i| {
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

pub fn PoolElementType(comptime components: []const CR.ComponentName) type {
    var fields: [5]StructField = undefined;
    const default_arch_list = comptime ArrayList(usize){};
    const arch_cache_arraylist = comptime ArrayList(ArchetypeCacheType(components));
    const arch_cache_default = comptime arch_cache_arraylist{};

    //~Field:pool_name: PoolName
    fields[0] = StructField{
        .name = "pool_name",
        .type = PR.PoolName,
        .alignment = @alignOf(PR.PoolName),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:access: StorageStrategy
    fields[1] = StructField{
        .name = "storage_strategy",
        .type = StorageStrategy,
        .alignment = @alignOf(StorageStrategy),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:access: ArchAccess
    fields[2] = StructField{
        .name = "access",
        .type = ArchetypeAccess,
        .alignment = @alignOf(ArchetypeAccess),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field: archetype_indices: AL(usize)
    fields[3] = StructField{
        .name = "archetype_indices",
        .type = ArrayList(usize),
        .alignment = @alignOf(ArrayList(usize)),
        .default_value_ptr = &default_arch_list,
        .is_comptime = false,
    };

    //~Field: archetype_cache: AL(ArchCache)
    fields[4] = StructField{
        .name = "archetype_cache",
        .type = arch_cache_arraylist,
        .alignment = @alignOf(arch_cache_arraylist),
        .is_comptime = false,
        .default_value_ptr = &arch_cache_default,
    };

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

pub fn findPoolElements(comptime components: []const CR.ComponentName) [countMatchingPools(components)]PoolElementType(components) {
    const PoolElement = PoolElementType(components);
    const count = countMatchingPools(components);
    var pool_elements: [count]PoolElement = undefined;
    var idx: usize = 0;

    // Check each registered pool type to see if it matches the query
    for(PR.pool_types, 0..) |pool_type, i| {
        // Assume the pool matches until proven otherwise
        var query_match = true;  // All query components exist in pool (req OR opt)
        var req_match = true;    // All query components exist in pool's REQ_MASK

        // Check if all query components exist in this pool
        for(components) |component| {
            const component_bit = MaskManager.Comptime.componentToBit(component);
            const in_pool = MaskManager.maskContains(pool_type.pool_mask, component_bit);

            // If component doesn't exist in pool at all, this pool can't match
            if(!in_pool) {
                query_match = false;
                req_match = false;
                break;  // Skip to next pool
            }

            // Component exists in pool, but is it required or optional?
            // Only check if we haven't already determined it's not a req_match
            if(req_match) {
                const contained_in_req = MaskManager.maskContains(pool_type.REQ_MASK, component_bit);
                if(!contained_in_req) {
                    // Component is optional, so we'll need Lookup access
                    req_match = false;
                }
            }
        }

        const pool_name: PR.PoolName = @enumFromInt(i);

        // Direct access: all query components are required in this pool
        // Every archetype in the pool is guaranteed to have them
        if(req_match) {
            pool_elements[idx] = PoolElement{.pool_name = pool_name, .access = .Direct, .storage_strategy = pool_type.storage_strategy};
            idx += 1;
        }
        // Lookup access: all query components exist but at least one is optional
        // Need to check each archetype individually to see if it matches
        else if(!req_match and query_match) {
            pool_elements[idx] = PoolElement{.pool_name = pool_name, .access = .Lookup, .storage_strategy = pool_type.storage_strategy};
            idx += 1;
        }
    }
    return pool_elements;
}
