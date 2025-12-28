const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const PM = @import("PoolManager.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const EM = @import("EntityManager.zig");
const PoolInterface = @import("PoolInterface.zig");
const StructField = std.builtin.Type.StructField;
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;
const QT = @import("QueryTypes.zig");

fn QueryResultType(
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

fn QueryResult(comptime PoolElement: type, comptime found_pool_elements: anytype) QueryResultType(PoolElement, found_pool_elements){
    var storage: QueryResultType(PoolElement, found_pool_elements) = undefined;
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

pub fn QueryType(comptime components: []const CR.ComponentName) type {
    const PoolElement = QT.PoolElementType(components);
    const found_pool_elements = comptime QT.findPoolElements(components);
    const POOL_COUNT = found_pool_elements.len;

    const QResultType = QueryResultType(PoolElement, &found_pool_elements);
    const QResult = QueryResult(PoolElement, &found_pool_elements);

    return struct {
        const Self = @This();
        const pool_count = POOL_COUNT;
        pub const MASK = MaskManager.Comptime.createMask(components);

        allocator: std.mem.Allocator,
        pool_manager: *PM.PoolManager,
        query_storage: QResultType = QResult,

        pool_index: usize = 0,
        archetype_index: usize = 0,

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PM.PoolManager) Self {
            var self = Self{
                .allocator = allocator,
                .pool_manager = pool_manager,
            };

            // Initialize the ArrayLists in each pool element
            inline for(std.meta.fields(QResultType)) |field| {
                var pool_element = &@field(self.query_storage, field.name);
                pool_element.archetype_indices = ArrayList(usize){};
                pool_element.archetype_cache = ArrayList(QT.ArchetypeCacheType(components)){};
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(QResultType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);
                pool_element.archetype_indices.deinit(self.allocator);
                pool_element.archetype_cache.deinit(self.allocator);
            }
        }

        pub fn cacheArchetypesFromPools(self: *Self) !void {
            inline for(std.meta.fields(QResultType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);
                switch (pool_element.pool_name) {
                    inline else => |pool_name|{
                        const pool = try self.pool_manager.getOrCreatePool(pool_name);
                        if(pool.pool_is_dirty){
                            for(pool.new_archetypes.items) |arch| {
                                if(pool_element.access == .Direct) {
                                    try self.cache(pool_element, pool, arch, null);
                                }
                                else {
                                    const archetype_bitmask = pool.mask_list.items[arch];
                                    if(MaskManager.maskContains(archetype_bitmask, Self.MASK)){
                                        try self.cache(pool_element, pool, arch, null);
                                    }
                                }
                            }

                            for(pool.reallocated_archetypes.items) |arch| {
                                const i = std.mem.indexOfScalar(usize, pool_element.archetype_indices.items, arch) orelse continue;
                                try self.cache(pool_element, pool, arch, i);
                            }
                        }
                    }
                }
            }
        }

        pub fn cache(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize, index_in_pool_elem: ?usize) !void {
           if(pool_element.storage_strategy == .ARCHETYPE){ 
               return self.cacheArchetype(pool_element, pool, archetype_index, index_in_pool_elem); 
           }
           else {
               return self.cacheSparseSet(pool_element, pool, archetype_index, index_in_pool_elem);
            }
        }
        ///Convert archetype storage into Query Struct and append it to query cache
        fn cacheArchetype(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize, index_in_pool_elem: ?usize) !void {
            const ArchCacheType = comptime QT.ArchetypeCacheType(components);
            var archetype_cache: ArchCacheType = undefined;
            const storage = &pool.archetype_list.items[archetype_index];

            // Iterate over component fields in the PoolElement type
            inline for(std.meta.fields(ArchCacheType)) |field| {
                // Only process component fields (skip metadata fields)
                // Only cache if this component exists in the archetype storage
                if (@hasField(@TypeOf(storage.*), field.name)) {
                    const slice = @field(storage, field.name).?.items;
                    @field(archetype_cache, field.name) = slice;
                }
            }

            if(index_in_pool_elem) |indx|{
                // Re-caching existing archetype - just update the cache
                pool_element.archetype_cache.items[indx] = archetype_cache;
            }
            else{
                // New archetype - add to both lists
                try pool_element.archetype_indices.append(self.allocator, archetype_index);
                try pool_element.archetype_cache.append(self.allocator, archetype_cache);
            }
        }

        fn cacheSparseSet(self: *Self, pool_element: anytype, pool: anytype, index_in_pool_elem: ?usize) !void {
            const ArchCacheType = comptime QT.ArchetypeCacheType(components);
            var archetype_cache: ArchCacheType = undefined;
            const virtual_archetype = pool.masks.

            inline for(std.meta.fields(ArchCacheType)) |field| {

            }
        }
        
        pub fn next(self: *Self) ?QT.ArchetypeCacheType(components){
            while(true){
                switch(self.pool_index){
                    inline 0...(pool_count - 1) =>|i|{
                        const field = std.meta.fields(QResultType)[i];
                        const pool_elem = &@field(self.query_storage, field.name);

                        if(pool_elem.archetype_cache.items.len > 0) {
                            const arch_cache = pool_elem.archetype_cache.items[self.archetype_index];
                            self.archetype_index += 1;

                            if(self.archetype_index >= pool_elem.archetype_cache.items.len){
                                self.archetype_index = 0;
                                self.pool_index += 1;
                            }

                            return arch_cache;
                        }
                        else {
                            self.pool_index += 1;
                            if(self.pool_index >= POOL_COUNT) {
                                self.archetype_index = 0;
                                self.pool_index = 0;

                                return null;
                            }
                        }
                    },
                    else => unreachable,
                }
            }
        }
    };
}
test "Compile" {
    const query = QueryType(&.{.Position, .Attack});
    _= query;
}

test "Basic Query" {
    const allocator = testing.allocator;
    var pool_manager = PM.PoolManager.init(allocator);

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
        .Attack = CR.Attack{.damage = 10.0, .crit_chance = 1},
        .AI = CR.AI{.state = 5, .target_id = 0},
    });
    _ = ent2;

    var query = QueryType(&.{.Health, .Attack}).init(allocator, &pool_manager);
    defer query.deinit();
    try query.cacheArchetypesFromPools();
}

test "Next" {
    const allocator = testing.allocator;
    var pool_manager = PM.PoolManager.init(allocator);

    var entity_manager = try EM.EntityManager.init(allocator);
    defer {
        pool_manager.deinit();
        entity_manager.deinit();
    }

    const enemy_pool = try pool_manager.getOrCreatePool(.EnemyPool);
    var enemy_interface = enemy_pool.getInterface(&entity_manager);
    
    const player_pool = try pool_manager.getOrCreatePool(.PlayerPool);
    var player_interface = player_pool.getInterface(&entity_manager);
    const ents_per_arch = 1;

    for(0..ents_per_arch) |_|{
        _ = try enemy_interface.createEntity(.{
            .Position = CR.Position{.x = 10, .y = 15},
        });
    }

    for(0..ents_per_arch) |_|{
        _ = try enemy_interface.createEntity(.{
            .Position = CR.Position{.x = 10, .y = 15},
            .Health = CR.Health{.current = 100, .max = 100},
        });
    }

    for(0..ents_per_arch) |_|{
        _ = try enemy_interface.createEntity(.{
            .Position = CR.Position{.x = 10, .y = 15},
            .Health = CR.Health{.current = 100, .max = 100},
            .Attack = CR.Attack{.damage = 50, .crit_chance = 10},
            .Velocity = CR.Velocity{.dx = 0, .dy = 1},
        });
    }

    for(0..ents_per_arch) |_|{
        _ = try player_interface.createEntity(.{
            .Position = CR.Position{.x = 5, .y = 5},
            .Health = CR.Health{.max = 50, .current = 25},
        });
    }

    for(0..ents_per_arch) |_|{
        _ = try player_interface.createEntity(.{
            .Position = CR.Position{.x = 10, .y = 15},
            .AI = CR.AI{.state = 5, .target_id = 0},
        });
    }

    for(0..ents_per_arch) |_|{
        _ = try player_interface.createEntity(.{
            .Position = CR.Position{.x = 10, .y = 15},
            .AI = CR.AI{.state = 5, .target_id = 0},
            .Attack = CR.Attack{.damage = 50, .crit_chance = 10},
        });
    }
    var query = QueryType(&.{.Position, .Velocity}).init(allocator, &pool_manager);
    defer query.deinit();
    try query.cacheArchetypesFromPools();

    while(query.next()) |batch|{
        for(batch.Position, batch.Velocity) |*pos, vel| {
            pos.x += vel.dx;
            pos.y += vel.dy;
        } 
    }

    while(query.next()) |batch|{
        for(batch.Position) |pos| {
            try testing.expect(pos.y == 16);
        }
    }
}
