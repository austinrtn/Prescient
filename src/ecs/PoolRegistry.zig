const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const ArchPool = @import("ArchetypePool.zig");

const general_components = std.meta.tags(cr.ComponentName);
pub const GeneralPool = ArchPool.ArchetypePoolType(.{
    .name = .GeneralPool,
    .req = null,
    .opt = general_components,
});

/// Basic movement pool for entities that can move
/// Required: (none)
/// Optional: Position, Velocity
pub const MovementPool = ArchPool.ArchetypePoolType(.{
    .name = .MovementPool,
    .req = &.{},
    .opt = &.{.Position, .Velocity}
});

/// Enemy entities with combat and AI capabilities
/// Required: (none)
/// Optional: Position, Velocity, Attack, Health, AI
pub const EnemyPool = ArchPool.ArchetypePoolType(.{
    .name = .EnemyPool,
    .req = &.{},
    .opt = &.{.Position, .Velocity, .Attack, .Health, .AI}
});

/// Player entities - must have a position
/// Required: Position
/// Optional: Health, Attack, Sprite, Player
pub const PlayerPool = ArchPool.ArchetypePoolType(.{
    .name = .PlayerPool,
    .req = &.{.Position},
    .opt = &.{.Health, .Attack, .Sprite, .Player, .AI}
});

/// Renderable entities that can be drawn to screen
/// Required: Position, Sprite
/// Optional: Velocity
pub const RenderablePool = ArchPool.ArchetypePoolType(.{
    .name = .RenderablePool,
    .req = &.{.Position, .Sprite},
    .opt = &.{.Velocity}
});

/// Combat entities that can fight
/// Required: Health, Attack
/// Optional: AI
pub const CombatPool = ArchPool.ArchetypePoolType(.{
    .name = .CombatPool,
    .req = &.{.Health, .Attack},
    .opt = &.{.AI}
});

pub const PoolName = enum(u32) {
    GeneralPool,
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
};

pub const pool_types = [_]type{
    GeneralPool,
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
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
