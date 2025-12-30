const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const EntityPool = @import("EntityPool.zig").EntityPool;
const PC = @import("PoolConfig.zig");

pub const PoolName = PC.PoolName;

const general_components = std.meta.tags(cr.ComponentName);
pub const GeneralPool = EntityPool(.{
    .name = .GeneralPool,
    .components = general_components,
    .storage_strategy = .ARCHETYPE,
});

/// Basic movement pool for entities that can move
/// Required: (none)
/// Optional: Position, Velocity
pub const MovementPool = EntityPool(.{
    .name = .MovementPool,
    .components = &.{.Position, .Velocity},
    .storage_strategy = .ARCHETYPE,
});

pub const UIPool = EntityPool(.{
    .name = .UIPool,
    .storage_strategy = .SPARSE,
    .components = &.{.Position, .Sprite},
});

/// Enemy entities with combat and AI capabilities
/// Required: (none)
/// Optional: Position, Velocity, Attack, Health, AI
pub const EnemyPool = EntityPool(.{
    .name = .EnemyPool,
    .components = &.{.Position, .Velocity, .Attack, .Health, .AI},
    .storage_strategy = .ARCHETYPE,
});

/// Player entities - must have a position
/// Required: Position
/// Optional: Health, Attack, Sprite, Player
pub const PlayerPool = EntityPool(.{
    .name = .PlayerPool,
    .req = &.{.Position},
    .components = &.{.Health, .Attack, .Sprite, .Player, .AI},
    .storage_strategy = .ARCHETYPE,
});

/// Renderable entities that can be drawn to screen
/// Required: Position, Sprite
/// Optional: Velocity
pub const RenderablePool = EntityPool(.{
    .name = .RenderablePool,
    .req = &.{.Position, .Sprite},
    .components = &.{.Velocity},
    .storage_strategy = .ARCHETYPE,
});

/// Combat entities that can fight
/// Required: Health, Attack
/// Optional: AI
pub const CombatPool = EntityPool(.{
    .name = .CombatPool,
    .req = &.{.Health, .Attack},
    .components = &.{.AI},
    .storage_strategy = .ARCHETYPE,
});

pub const pool_types = [_]type{
    GeneralPool,
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
    UIPool,
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
