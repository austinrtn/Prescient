const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig");
const PR = @import("PoolRegistry.zig");
const PM = @import("PoolManager.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const EM = @import("EntityManager.zig");
const QT = @import("QueryTypes.zig");

pub fn QueryType(comptime components: []const CR.ComponentName) type {
    // PoolElementsType generates a heterogeneous struct where each field
    // has its own type with comptime POOL_NAME and STORAGE_STRATEGY
    const QResultType = QT.PoolElementsType(components);
    const POOL_COUNT = std.meta.fields(QResultType).len;

    return struct {
        const Self = @This();
        const pool_count = POOL_COUNT;
        pub const MASK = MaskManager.Comptime.createMask(components);

        allocator: std.mem.Allocator,
        updated: bool = false,
        pool_manager: *PM.PoolManager,
        query_storage: QResultType = QT.findPoolElements(components),

        pool_index: usize = 0,
        archetype_index: usize = 0,

        // Track sparse batch allocations for cleanup
        sparse_batch_allocs: ArrayList(QT.ArchetypeCacheType(components)) = .{},

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
                pool_element.sparse_cache = ArrayList(usize){};
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(QResultType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);

                // Free pointer arrays in archetype_cache
                for(pool_element.archetype_cache.items) |arch_cache| {
                    inline for(std.meta.fields(@TypeOf(arch_cache))) |cache_field| {
                        self.allocator.free(@field(arch_cache, cache_field.name));
                    }
                }

                pool_element.archetype_indices.deinit(self.allocator);
                pool_element.archetype_cache.deinit(self.allocator);
                pool_element.sparse_cache.deinit(self.allocator);
            }

            // Free sparse batch allocations
            for(self.sparse_batch_allocs.items) |batch| {
                inline for(std.meta.fields(@TypeOf(batch))) |batch_field| {
                    self.allocator.free(@field(batch, batch_field.name));
                }
            }
            self.sparse_batch_allocs.deinit(self.allocator);
        }

        pub fn update(self: *Self) !void {
            // Free previous sparse batch allocations before starting new iteration cycle
            for(self.sparse_batch_allocs.items) |batch| {
                inline for(std.meta.fields(@TypeOf(batch))) |batch_field| {
                    self.allocator.free(@field(batch, batch_field.name));
                }
            }
            self.sparse_batch_allocs.clearRetainingCapacity();
            try self.cacheArchetypesFromPools();
            self.updated = true;
        }

        pub fn cacheArchetypesFromPools(self: *Self) !void {
            inline for(std.meta.fields(QResultType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);
                const PoolElemType = @TypeOf(pool_element.*);

                // POOL_NAME is comptime - no inline switch needed!
                const pool = try self.pool_manager.getOrCreatePool(PoolElemType.POOL_NAME);

                //Cache new archetypes / virtual archetypes
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

                // Update reallocated archetypes (archetype pools only)
                if(PoolElemType.STORAGE_STRATEGY == .ARCHETYPE) {
                    for(pool.reallocated_archetypes.items) |arch| {
                        const i = std.mem.indexOfScalar(usize, pool_element.archetype_indices.items, arch) orelse continue;
                        try self.cache(pool_element, pool, arch, i);
                    }
                }
            }
        }

        pub fn cache(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize, index_in_pool_elem: ?usize) !void {
            if(@TypeOf(pool.*).storage_strategy == .ARCHETYPE) {
               return self.cacheArchetype(pool_element, pool, archetype_index, index_in_pool_elem);
            } else {
                try pool_element.sparse_cache.append(self.allocator, archetype_index);
            }
        }
        ///Convert archetype storage into Query Struct and append it to query cache
        fn cacheArchetype(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize, index_in_pool_elem: ?usize) !void {
            const ArchCacheType = comptime QT.ArchetypeCacheType(components);
            var archetype_cache: ArchCacheType = undefined;
            const storage = &pool.archetype_list.items[archetype_index];

            // Build entities slice
            const entities_slice = storage.entities.items;
            const entities_array = try self.allocator.alloc(EM.Entity, entities_slice.len);
            @memcpy(entities_array, entities_slice);
            archetype_cache.entities = entities_array;

            // Build pointer arrays for each component
            inline for(components) |comp| {
                const field_name = @tagName(comp);
                const ComponentType = CR.getTypeByName(comp);
                const value_slice = @field(storage, field_name).?.items;

                // Allocate pointer array
                const ptr_array = try self.allocator.alloc(*ComponentType, value_slice.len);
                for (value_slice, 0..) |*item, idx| {
                    ptr_array[idx] = item;
                }
                @field(archetype_cache, field_name) = ptr_array;
            }

            if(index_in_pool_elem) |indx|{
                // Re-caching existing archetype - free old pointer arrays first
                const old_cache = pool_element.archetype_cache.items[indx];
                self.allocator.free(old_cache.entities);
                inline for(components) |comp| {
                    self.allocator.free(@field(old_cache, @tagName(comp)));
                }
                pool_element.archetype_cache.items[indx] = archetype_cache;
            }
            else{
                // New archetype - add to both lists
                try pool_element.archetype_indices.append(self.allocator, archetype_index);
                try pool_element.archetype_cache.append(self.allocator, archetype_cache);
            }
        }

        pub fn next(self: *Self) !?QT.ArchetypeCacheType(components){
            // Only require update() before first iteration (at start position)
            if(self.pool_index == 0 and self.archetype_index == 0 and !self.updated) {
                return error.QueryNotUpdated;
            }

            while(true){
                // Check if we've exhausted all pools
                if(self.pool_index >= POOL_COUNT) {
                    self.pool_index = 0;
                    self.archetype_index = 0;
                    return null;
                }

                switch(self.pool_index){
                    inline 0...(pool_count - 1) =>|i|{
                        const field = std.meta.fields(QResultType)[i];
                        const pool_elem = &@field(self.query_storage, field.name);
                        const PoolElemType = @TypeOf(pool_elem.*);

                        if(PoolElemType.STORAGE_STRATEGY == .ARCHETYPE) {
                            if(pool_elem.archetype_cache.items.len > 0) {
                                const batch = pool_elem.archetype_cache.items[self.archetype_index];
                                self.archetype_index += 1;

                                if(self.archetype_index >= pool_elem.archetype_cache.items.len){
                                    self.archetype_index = 0;
                                    self.pool_index += 1;
                                }

                                return batch;
                            }
                            else {
                                self.pool_index += 1;
                                if(self.pool_index >= POOL_COUNT) {
                                    self.archetype_index = 0;
                                    self.pool_index = 0;
                                    return null;
                                }
                            }
                        }
                        else if(PoolElemType.STORAGE_STRATEGY == .SPARSE){
                            if(self.archetype_index < pool_elem.sparse_cache.items.len) {
                                // POOL_NAME is comptime - no inline switch needed!
                                const pool = self.pool_manager.getOrCreatePool(PoolElemType.POOL_NAME) catch unreachable;

                                const v_arch_index = pool_elem.sparse_cache.items[self.archetype_index];
                                const storage_indexes = pool.virtual_archetypes.items[v_arch_index];

                                var batch: QT.ArchetypeCacheType(components) = undefined;

                                // Build entities slice
                                const entities_array = self.allocator.alloc(EM.Entity, storage_indexes.items.len) catch unreachable;
                                for (storage_indexes.items, 0..) |ent_index, idx| {
                                    entities_array[idx] = pool.storage.entities.items[ent_index].?;
                                }
                                batch.entities = entities_array;

                                inline for(components) |component| {
                                    const ComponentType = CR.getTypeByName(component);
                                    // Allocate pointer array
                                    const ptr_array = self.allocator.alloc(*ComponentType, storage_indexes.items.len) catch unreachable;

                                    for (storage_indexes.items, 0..) |ent_index, idx| {
                                        ptr_array[idx] = &@field(pool.storage, @tagName(component)).items[ent_index].?;
                                    }
                                    @field(batch, @tagName(component)) = ptr_array;
                                }

                                self.archetype_index += 1;

                                if(self.archetype_index >= pool_elem.sparse_cache.items.len){
                                    self.archetype_index = 0;
                                    self.pool_index += 1;
                                }

                                // Track allocation for cleanup
                                self.sparse_batch_allocs.append(self.allocator, batch) catch unreachable;
                                return batch;
                            }
                            else {
                                self.pool_index += 1;
                                if(self.pool_index >= POOL_COUNT) {
                                    self.archetype_index = 0;
                                    self.pool_index = 0;

                                    return null;
                                }
                            }
                        }
                    },
                    else => unreachable,
                }
            }
        }
    };
}
