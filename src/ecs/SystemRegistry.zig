const std = @import("std");
const Movement = @import("../systems/MovementSystem.zig").MovementSystem;

pub const SystemName = enum {
    Movement,
};

pub const SystemTypes = [_]type {
    Movement,
};

pub fn getTypeByName(comptime system_name: SystemName) type {
    const index = @intFromEnum(system_name);
    return SystemTypes[index];
}
