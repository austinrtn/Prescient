const std = @import("std");

pub const Movement = @import("../systems/Movement.zig").Movement;

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
