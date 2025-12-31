const std = @import("std");

pub const SystemName = enum {

};

pub const SystemTypes = [_]type {

};

pub fn getTypeByName(comptime system_name: SystemName) type {
    const index = @intFromEnum(system_name);
    return SystemTypes[index];
}
