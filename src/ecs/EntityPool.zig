const std = @import("std");
const ArchetypePool = @import("ArchetypePool.zig").ArchetypePoolType;
const SparseSetPool = @import("SparseSetPool.zig").SparseSetPoolType;
const PC = @import("../registries/PoolRegistry.zig");

pub const PoolConfig = PC.PoolConfig;
pub const PoolName = PC.PoolName;

pub fn EntityPool(comptime config: PoolConfig) type {
    if(config.storage_strategy == .ARCHETYPE) {
        return ArchetypePool(config);
    }
    else {
        return SparseSetPool(config);
    }
}
