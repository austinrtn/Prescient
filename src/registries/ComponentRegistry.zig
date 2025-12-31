const std = @import("std");

pub const Position = @import("../components/Position.zig").Position;
pub const Velocity = @import("../components/Velocity.zig").Velocity;

pub const ComponentName = enum {
    Position,
    Velocity,
};

pub const ComponentTypes = [_]type {
    Position,
    Velocity,
};

pub fn getTypeByName(comptime component_name: ComponentName) type {
    const index = @intFromEnum(component_name);
    return ComponentTypes[index];
}
