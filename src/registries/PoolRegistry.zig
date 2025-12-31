const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
const StorageStrategy = @import("../ecs/StorageStrategy.zig").StorageStrategy;

// GeneralPool - includes all registered components
const general_components = std.meta.tags(cr.ComponentName);
pub const GeneralPool = EntityPool(.{
    .name = .GeneralPool,
    .components = general_components,
    .storage_strategy = .SPARSE,
});

// Add more pools below...

pub const PoolName = enum(u32) {
    GeneralPool,
    // Add more pool names here
};

pub const pool_types = [_]type{
    GeneralPool,
    // Add more pools here
};

pub fn getPoolFromName(comptime pool: PoolName) type {
    return pool_types[@intFromEnum(pool)];
}

/// Check at compile time if a pool contains a specific component
pub fn poolHasComponent(comptime pool_name: PoolName, comptime component: cr.ComponentName) bool {
    const PoolType = getPoolFromName(pool_name);
    const pool_components = PoolType.COMPONENTS;

    for (pool_components) |comp| {
        if (comp == component) {
            return true;
        }
    }
    return false;
}

pub const PoolConfig = struct {
    name: PoolName,
    req: ?[]const cr.ComponentName = null,
    components: ?[]const cr.ComponentName = null,
    storage_strategy: StorageStrategy,
};
