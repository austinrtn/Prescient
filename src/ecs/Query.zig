const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const EM = @import("EntityManager.zig");
const PoolInterface = @import("PoolInterface.zig");
const StructField = std.builtin.Type.StructField;

// Determines how a pool's archetypes are accessed during query iteration
const ArchetypeAccess = enum{
    // All archetypes in the pool are guaranteed to match the query (all query components are required)
    Direct,
    // Archetypes must be individually checked since some query components are optional
    Lookup,
};

fn ArchetypeCache(comptime components: []const CR.ComponentName) type {
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

//const ArchetypeCache = struct {
//  Position: []PositionComponent,
//  Velocity: []VelocityComponent,
//};

fn PoolElementType(comptime components: []const CR.ComponentName) type {
    var fields: [4]StructField = undefined;
    const default_arch_list = comptime ArrayList(usize){};
    const arch_cache_arraylist = comptime ArrayList(ArchetypeCache(components));
    const arch_cache_default = comptime arch_cache_arraylist{};

    //~Field:pool_name: PoolName 
    fields[0] = StructField{
        .name = "pool_name",
        .type = PR.PoolName,
        .alignment = @alignOf(PR.PoolName),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:access: ArchAccess
    fields[1] = StructField{
        .name = "access",
        .type = ArchetypeAccess,
        .alignment = @alignOf(ArchetypeAccess),
        .default_value_ptr = null,
        .is_comptime = false,
    };
    
    //~Field: archetype_indices: AL(usize)
    fields[2] = StructField{
        .name = "archetype_indices",
        .type = ArrayList(usize),
        .alignment = @alignOf(ArrayList(usize)),
        .default_value_ptr = &default_arch_list,
        .is_comptime = false,
    };

    //~Field: archetype_cache: AL(ArchCache)
    fields[3] = StructField{
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

fn countMatchingPools(comptime components: []const CR.ComponentName) comptime_int {
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

fn findPoolElements(comptime components: []const CR.ComponentName) [countMatchingPools(components)]PoolElementType(components) {
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
            pool_elements[idx] = PoolElement{.pool_name = pool_name, .access = .Direct};
            idx += 1;
        }
        // Lookup access: all query components exist but at least one is optional
        // Need to check each archetype individually to see if it matches
        else if(!req_match and query_match) {
            pool_elements[idx] = PoolElement{.pool_name = pool_name, .access = .Lookup};
            idx += 1;
        }
    }
    return pool_elements;
}

fn QueryStorageType(
    comptime PoolElement: type,
    comptime found_pool_elements: anytype,
    ) type {
    var fields: [found_pool_elements.len]std.builtin.Type.StructField = undefined;

    //~Field: pool_name: PoolElement
    for(found_pool_elements, 0..) |pool_element, i| {
        fields[i] = std.builtin.Type.StructField{
            .name = @tagName(pool_element.pool_name),
            .type = PoolElement,
            .alignment = @alignOf(PoolElement),
            .is_comptime = false,
            .default_value_ptr = null,
        };
    }

     return @Type(.{
        .@"struct" = .{
            .fields = &fields,
            .layout = .auto,
            .backing_integer = null,
            .decls = &.{},
            .is_tuple = false,
        }
    });
}

fn QueryStorage(comptime PoolElement: type, comptime found_pool_elements: anytype) QueryStorageType(PoolElement, found_pool_elements){
    var storage: QueryStorageType(PoolElement, found_pool_elements) = undefined;
    for(found_pool_elements) |pool_element| {
        const field_name = @tagName(pool_element.pool_name);
        @field(storage, field_name) = pool_element;
    }

    return storage;
}

//*************************************
//***End of the MF meta programming ***
//*************************************
//

pub fn Query(comptime components: []const CR.ComponentName) type {
    const PoolElement = PoolElementType(components);
    const found_pool_elements = comptime findPoolElements(components);
    const POOL_COUNT = found_pool_elements.len;

    const QStorageType = QueryStorageType(PoolElement, &found_pool_elements);
    const QStorage = QueryStorage(PoolElement, &found_pool_elements);

    return struct {
        const Self = @This();
        const pool_count = POOL_COUNT;
        pub const MASK = MaskManager.Comptime.createMask(components);

        allocator: std.mem.Allocator,
        pool_manager: *PR.PoolManager(),
        query_storage: QStorageType = QStorage,
        
        pool_index: usize = 0,
        archetype_index: usize = 0,

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PR.PoolManager()) Self {
            const self = Self{
                .allocator = allocator,
                .pool_manager = pool_manager,
            };

            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(QStorageType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);
                pool_element.archetype_indices.deinit(self.allocator);
                pool_element.archetype_cache.deinit(self.allocator);
            }
        }

        pub fn cacheArchetypesFromPools(self: *Self) !void {
            inline for(std.meta.fields(QStorageType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);
                switch (pool_element.pool_name) {
                    inline else => |pool_name|{
                        const pool = try self.pool_manager.getOrCreatePool(pool_name);
                        for(pool.new_archetypes.items) |arch| {
                            if(pool_element.access == .Direct) {
                                try self.cache(pool_element, pool, arch);
                            }
                            else {
                                const archetype_bitmask = pool.mask_list.items[arch];
                                if(MaskManager.maskContains(archetype_bitmask, Self.MASK)){
                                    try self.cache(pool_element, pool, arch);
                                }
                            }
                        }
                    }
                }
            }
        }

        pub fn cache(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize) !void {
            const storage = &pool.archetype_list.items[archetype_index];

            // Add archetype index to the list
            try pool_element.archetype_indices.append(self.allocator, archetype_index);

            // Iterate over component fields in the PoolElement type
            inline for(std.meta.fields(@TypeOf(pool_element.*.archetype_cache))) |field| {
            // Only process component fields (skip metadata fields)
                // Only cache if this component exists in the archetype storage
                if (@hasField(@TypeOf(storage.*), field.name)) {
                    const slice = @field(storage, field.name).?.items;
                    try @field(pool_element.archetypes_list, field.name).append(self.allocator, slice);
                }
            }
        }

        //Check each pool to see which archetypes match the query
        // pub fn update(self: *Self) !void{
        //     var archetypes_list: ArrayList(MaskManager.Mask) = .{};
        //
        //     inline for(PR.pool_types, 0..) |_, i| {
        //         const pool_name: PR.PoolName = @enumFromInt(i);
        //         const pool_field = @tagName(pool_name);
        //         
        //         if(@hasField(@TypeOf(self.pool_storage), pool_field)) {
        //             const pool_element = @field(self.pool_storage, pool_field);
        //             const pool_instance = try self.pool_manager.getOrCreatePool(pool_name);
        //
        //             if(pool_element.access == .Direct) {
        //                 try archetypes_list.appendSlice(self.allocator, pool_instance.mask_list.items);
        //             }
        //             else if(pool_element.access == .Lookup) {
        //                 for(pool_instance.mask_list.items) |archetype_mask|{
        //                     var has_components: bool = true;
        //                     inline for(components) |component|{
        //                         const bit = MaskManager.Comptime.componentToBit(component);
        //                         if(!MaskManager.maskContains(archetype_mask, bit)) {
        //                             has_components = false;
        //                             break;
        //                         }
        //                     }
        //                     if(has_components) try archetypes_list.append(self.allocator, archetype_mask);
        //                 }
        //             }
        //         }
        //     } 
        //     self.cached_archetypes = archetypes_list;
        // }
        //
        // pub fn next(self: *Self) !?ComponentDataContainer {
        //     if(self.pool_index == self.pool_count) return null;
        //     
        //     const archetype
        // }
    };
}

test "Compile" {
    const query = Query(&.{.Position, .Attack});
    _= query;
}

test "Basic Query" {
    const allocator = testing.allocator;
    var pool_manager = PR.PoolManager().init(allocator);

    var entity_manager = try EM.EntityManager.init(allocator);
    defer {
        pool_manager.deinit();
        entity_manager.deinit();
    }

    const combat_pool = try pool_manager.getOrCreatePool(.CombatPool);
    var combat_interface = combat_pool.getInterface(&entity_manager);
    const ent1 = try combat_interface.createEntity(.{
        .Health = CR.Health{.current = 100, .max = 100},
        .Attack = .{.damage = 20.0, .crit_chance = 50},
    });
    _ = ent1;
    const ent2 = try combat_interface.createEntity(.{
        .Health = CR.Health{.current = 50, .max = 100},
        .Attack = .{.damage = 10.0, .crit_chance = 50},
        .AI = CR.AI{.state = 5, .target_id = 0},
    });
    _ = ent2;

    var query = Query(&.{.Health, .Attack}).init(allocator, &pool_manager);
    defer query.deinit();
    try query.cacheArchetypesFromPools();
}
