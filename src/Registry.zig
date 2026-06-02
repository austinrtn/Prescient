const PoolConfig = @import("PoolRegistry.zig").PoolConfig;
const CR = @import("ComponentRegistry.zig");
const ComponentDesc = CR.ComponentDesc;

pub const Registry = struct {
    pub const comp_descs = [_]ComponentDesc {
        .{.name = "pos", .T = struct{x: f32, y: f32}},
        .{.name = "vel", .T = struct{xvel: f32, yvel: f32}},
        .{.name = "id", .T = u32},
    };

    pub const PoolConfigs = [_]PoolConfig{
        .{
            .name = "general", 
            .components = &.{.pos, .vel, .id},
            .storage_strategy = .archetype,
        },
        .{
            .name = "sparse", 
            .components = &.{.pos, .vel, .id},
            .storage_strategy = .sparse,
        },
    };
};
