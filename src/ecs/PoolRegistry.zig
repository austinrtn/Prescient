const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const ArchPool = @import("ArchetypePool.zig");

/// Basic movement pool for entities that can move
/// Required: (none)
/// Optional: Position, Velocity
pub const MovementPool = ArchPool.ArchetypePoolType(&.{}, &.{.Position, .Velocity}, .MovementPool);

/// Enemy entities with combat and AI capabilities
/// Required: (none)
/// Optional: Position, Velocity, Attack, Health, AI
pub const EnemyPool = ArchPool.ArchetypePoolType(&.{}, &.{.Position, .Velocity, .Attack, .Health, .AI}, .EnemyPool);

/// Player entities - must have a position
/// Required: Position
/// Optional: Health, Attack, Sprite, Player
pub const PlayerPool = ArchPool.ArchetypePoolType(&.{.Position}, &.{.Health, .Attack, .Sprite, .Player, .AI}, .PlayerPool);

/// Renderable entities that can be drawn to screen
/// Required: Position, Sprite
/// Optional: Velocity
pub const RenderablePool = ArchPool.ArchetypePoolType(&.{.Position, .Sprite}, &.{.Velocity}, .RenderablePool);

/// Combat entities that can fight
/// Required: Health, Attack
/// Optional: AI
pub const CombatPool = ArchPool.ArchetypePoolType(&.{.Health, .Attack}, &.{.AI}, .CombatPool);

pub const PoolName = enum(u32) {
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
};

pub const pool_types = [_]type{
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
};

pub fn getPoolFromName(comptime pool: PoolName) type {
    return pool_types[@intFromEnum(pool)];
}
