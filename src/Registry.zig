const std = @import("std");
const CompRegistryMod = @import("ComponentRegistry.zig");
const CompDesc = CompRegistryMod.ComponentDesc;
const CompRegistryT = CompRegistryMod.ComponentRegistry;

const comp_descs = [_]CompDesc{
    .{.name = "pos", .T = struct{x: f32, y: f32}},
    .{.name = "vel", .T = struct{xvel: f32, yvel: f32}},
};

pub const Registry = struct {
    pub const Component = CompRegistryT(&comp_descs);
};