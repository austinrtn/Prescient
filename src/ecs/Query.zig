const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PoolInterface = @import("PoolInterface.zig");

// Determines how a pool's archetypes are accessed during query iteration
const ArchetypeAccess = enum{
    // All archetypes in the pool are guaranteed to match the query (all query components are required)
    Direct,
    // Archetypes must be individually checked since some query components are optional
    Lookup,
};

const PoolElement = struct {
    pool_name: PR.pool_name,
    access: ArchetypeAccess,
    archetype_indices: ArrayList(u32) = .{},
};

pub fn Query(comptime components: []const CR.ComponentName) type {
    // At compile time, find all pools that contain the queried components
    const found_pool_elements = comptime blk: {
        var pool_elements: [PR.pool_types.len] PoolElement = undefined;
        var count: usize = 0;

        // Check each registered pool type to see if it matches the query
        for(PR.pool_types, 0..) |pool_type, i| {
            // Assume the pool matches until proven otherwise
            var query_match = true;  // All query components exist in pool (req OR opt)
            var req_match = true;    // All query components exist in pool's REQ_MASK

            // Check if all query components exist in this pool
            for(components) |component| {
                const component_bit = MM.Comptime.componentToBit(component);
                const in_pool = MM.maskContains(pool_type.pool_mask, component_bit);

                // If component doesn't exist in pool at all, this pool can't match
                if(!in_pool) {
                    query_match = false;
                    req_match = false;
                    break;  // Skip to next pool
                }

                // Component exists in pool, but is it required or optional?
                // Only check if we haven't already determined it's not a req_match
                if(req_match) {
                    const contained_in_req =  MM.maskContains(pool_type.REQ_MASK, component_bit);
                    if(!contained_in_req) {
                        // Component is optional, so we'll need Lookup access
                        req_match = false;
                    }
                }
            }

            const pool_name: PR.pool_name = @enumFromInt(i);

            // Direct access: all query components are required in this pool
            // Every archetype in the pool is guaranteed to have them
            if(req_match) {
                const pool_element = PoolElement{.pool_name = pool_name, .access = .Direct};
                pool_elements[count] = pool_element;
                count += 1;
            }
            // Lookup access: all query components exist but at least one is optional
            // Need to check each archetype individually to see if it matches
            else if(!req_match and query_match) {
                const pool_element = PoolElement{.pool_name = pool_name, .access = .Lookup};
                pool_elements[count] = pool_element;
                count += 1;
            }
        }

        break :blk pool_elements[0..count];
    };

    const ComponentDataContainer = comptime blk: {
        var fields:[components.len]std.builtin.Type.StructField = undefined;
        for(components, 0..) |component, i| {
            const name = @tagName(component);
            const T = CR.getTypeByName(component);
            fields[i] = std.builtin.Type.StructField{
                .name = name,
                .type = ArrayList(T),
                .alignment = @alignOf(ArrayList(T)),
                .default_value_ptr = null,
                .is_comptime = false,
            };
        }
        break :blk @Type(.{
            .@"struct" = .{
                .fields = &fields,
                .layout = .auto,
                .backing_integer = null,
                .decls = &.{},
                .is_tuple = false,
            }
        });
    };

    // Create a struct type to hold all matching pool elements
    // Each field is named after the pool and contains a PoolElement
    const QueryStorage = comptime blk: {
        var fields: [found_pool_elements.len]std.builtin.Type.StructField = undefined;

        for(found_pool_elements, 0..) |pool_element, i| {
            fields[i] = std.builtin.Type.StructField{
                .name = @tagName(pool_element.pool_name),
                .type = PoolElement,
                .alignment = @alignOf(PoolElement),
                .is_comptime = false,
                .default_value_ptr = null,
            };
        }

        const storage = @Type(.{
            .@"struct" = .{
                .fields = &fields,
                .layout = .auto,
                .backing_integer = null,
                .decls = &.{},
                .is_tuple = false,
            }
        });
        break :blk storage;
    };
    
    // Pre-populate the storage with pool elements at compile time
    const POOL_STORAGE = comptime blk: {
        var pool_storage: QueryStorage = undefined;
        for(found_pool_elements) |pool_element| {
            const field_name = @tagName(pool_element.pool_name);
            @field(pool_storage, field_name) = pool_element;
        }

        break :blk pool_storage;
    };

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        pool_manager: *PR.PoolManager(),
        pool_storage: QueryStorage = POOL_STORAGE,
        cached_archetypes: ArrayList(CR.ComponentMask) = {},

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PR.PoolManager()) Self {
            const self = Self{
                .allocator = allocator,
                .pool_manager = pool_manager,
            };

            return self;
        }

        pub fn update(self: *Self) !ComponentDataContainer {
            var archetypes_list: ArrayList(CR.ComponentMask) = .{};

            inline for(PR.pool_types, 0..) |_, i| {
                const pool_name: PR.pool_name = @enumFromInt(i);
                const pool_field = @tagName(pool_name);
                if(@hasField(@TypeOf(self.pool_storage), pool_field)) {
                    const pool_element = @field(self.pool_storage, pool_field);
                    const pool_instance = try self.pool_manager.getOrCreatePool(pool_name);

                    if(pool_element.access == .Direct) {
                        try archetypes_list.appendSlice(self.allocator, pool_instance.mask_list.items);
                    }
                    else if(pool_element.access == .Lookup) {
                        for(pool_instance.mask_list.items) |archetype_mask|{
                            var has_components: bool = true;
                            inline for(components) |component|{
                                const bit = MM.Comptime.componentToBit(component);
                                if(!MM.maskContains(archetype_mask, bit)) {
                                    has_components = false;
                                    break;
                                }
                            }
                            if(has_components) try archetypes_list.append(self.allocator, archetype_mask);
                        }
                    }
                }
            } 
            return archetypes_list;
        }
    };
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
    var results = try query.query();
    defer results.deinit(allocator);

    std.debug.print("\nRESULTS: {any}\n", .{results});
}
