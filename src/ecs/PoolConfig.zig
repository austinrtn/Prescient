const CR = @import("../registries/ComponentRegistry.zig");
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;

pub const PoolName = enum(u32) {
    GeneralPool,
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
    UIPool,
};

pub const PoolConfig = struct {
    name: PoolName,
    req: ?[]const CR.ComponentName = null,
    components: ?[]const CR.ComponentName = null,
    storage_strategy: StorageStrategy,
};
