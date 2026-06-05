const std = @import("std");
const PR = @import("PoolRegistry.zig").PoolRegistry;
const ArchetypePool = @import("ArchetypePool.zig").ArchetypePool;
const SparseSetPool = @import("SparseSetPool.zig").SparseSetPool;

pub fn EntPool(comptime pool_config: PR.Config) type {
    if (pool_config.storage_strategy == .archetype) return ArchetypePool(pool_config) else return SparseSetPool(pool_config);
}
