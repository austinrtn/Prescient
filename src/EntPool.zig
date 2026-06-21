const std = @import("std");
const PR = @import("PoolRegistry.zig").PoolRegistry;
const ArchetypePool = @import("ArchetypePool.zig").ArchetypePool;
const SparseSetPool = @import("SparseSetPool.zig").SparseSetPool;

pub fn EntPool(comptime pool: PR.Enum) type {
    const pool_config = PR.GetPoolConfig(pool);
    
    switch (pool_config.storage_strategy) {
        .archetype => return ArchetypePool(pool_config),
        .sparse_set => return SparseSetPool(pool, pool_config),
    }
}
