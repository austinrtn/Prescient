const std = @import("std");
const PR = @import("PoolRegistry.zig").PoolRegistry;
const ArchetypePool = @import("ArchetypePool.zig").ArchetypePool;
const SparseSetPool = @import("SparseSetPool.zig").SparseSetPool;

pub fn EntPool(comptime TAG: PR.Enum) type {
    const Config = PR.GetPoolConfig(TAG);

    switch (Config.storage_strategy) {
        .archetype => return ArchetypePool(TAG),
        .sparse_set => return SparseSetPool(TAG),
    }
}
