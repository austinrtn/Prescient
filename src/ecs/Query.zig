const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const MM = @import("MaskManager.zig");

const ArchetypeAccess = enum{
    Direct,
    Lookup,
};

const PoolElement = struct {
    pool_name: PR.pool_name,
    access: ArchetypeAccess,
    archetype_indecies: ArrayList(usize) = .{},
};

pub fn Query(comptime components: []const CR.ComponentName) type {
    const found_pool_elements = comptime blk: {
        var pool_elements: [PR.pool_types.len] PoolElement = undefined;
        var count: usize = 0;
        
        for(PR.pool_types, 0..) |pool_type, i| {
            var query_match = true;
            var req_match = true;

            for(components) |component| {
                const component_bit = MM.Comptime.componentToBit(component);
                const in_pool = MM.maskContains(pool_type.pool_mask, component_bit);
                if(!in_pool) {
                    query_match = false;
                    req_match = false;
                    break;
                }

                if(req_match) {
                    const contained_in_req =  MM.maskContains(pool_type.REQ_MASK, component_bit);
                    if(!contained_in_req) {
                        req_match = false;
                    }
                }
            }
            
            const pool_name: PR.pool_name = @enumFromInt(i);
            if(req_match) {
                const pool_element = PoolElement{.pool_name = pool_name, .access = .Direct};
                pool_elements[count] = pool_element;
                count += 1;
            } 
            else if(!req_match and query_match) {
                const pool_element = PoolElement{.pool_name = pool_name, .access = .Lookup};
                pool_elements[count] = pool_element;
                count += 1; 
            }
        }

        break :blk pool_elements[0..count];
    };

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
                .decls = .{},
                .is_tuple = false,
            }
        });
        break :blk storage;
    };
    
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
        pool_storage: QueryStorage,

        pub fn init(allocator: std.mem.Allocator) Self {
            const self = Self{
                .allocator = allocator,
                .pool_storage = POOL_STORAGE,
            };

            return self;
        }
    };
}
