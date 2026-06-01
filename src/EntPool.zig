const std = @import("std");
const PR = @import("PoolRegistry.zig").PoolRegistry;
const ArchetypePool = @import("ArchetypePool.zig").ArchetypePool;
const SparsePool = @import("SparsePool.zig").SparsePool;

pub fn EntPool(comptime pool_config: PR.Conifg) type {
    if(pool_config.storage_strategy == .archetype) return ArchetypePool(pool_config)
    else return SparsePool(pool_config);
}
