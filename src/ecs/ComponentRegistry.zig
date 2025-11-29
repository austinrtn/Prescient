const std = @import("std");
pub const Position = @import("../components/Position.zig").Position;
pub const Velocity = @import("../components/Velocity.zig").Velocity;
pub const Attack = @import("../components/Attack.zig").Attack;
pub const Health = @import("../components/Health.zig").Health;
pub const Sprite = @import("../components/Sprite.zig").Sprite;
pub const AI = @import("../components/AI.zig").AI;
pub const Player = @import("../components/Player.zig").Player;

/// Enum of all registered component types.
/// Add new components here and to ComponentTypes array.
pub const ComponentName = enum {
    Position,
    Velocity,
    Attack,
    Health,
    Sprite,
    AI,
    Player,
};

/// Array mapping ComponentName enum values to their actual types.
/// Must be kept in sync with ComponentName enum order.
pub const ComponentTypes = [_]type {
    Position,
    Velocity,
    Attack,
    Health,
    Sprite,
    AI,
    Player,
};

/// Convert a ComponentName to its corresponding type at compile time.
pub fn getTypeByName(comptime component_name: ComponentName) type{
    const index = @intFromEnum(component_name);
    return ComponentTypes[index];
}
