const std = @import("std");
const Io = std.Io;

const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;
const Pools = @import("Registry.zig").Registry.EntPools;
const Registry = @import("Registry.zig").Registry;
const EntPool = @import("EntPool.zig").EntPool;
const ArchStore = @import("ArchetypeStorage.zig").Archetype;
const Prescient = @import("Prescient.zig").Prescient;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var prescient: Prescient = .init(gpa);
    defer prescient.deinit();

    const point_pool: *EntPool(Registry.PoolConfigs[0]) = prescient.getPool(.general);

    const Point = ComponentRegistry.GetTypeOfComponents(
        &.{.pos, .vel},
        false
    );

    const PointWithId = ComponentRegistry.GetTypeOfComponents(
        &.{.pos, .vel, .id},
        false
    );

    const point: Point = .{.pos = .{.x = 1, .y = 1}, .vel = .{.xvel = 1, .yvel = 1}};
    const point2: Point = .{.pos = .{.x = -100, .y = -100}, .vel = .{.xvel = -2, .yvel = -2}};
    const point3: PointWithId = .{.pos = .{.x = -100, .y = -100}, .vel = .{.xvel = -2, .yvel = -2}, .id = 0};

    try point_pool.append(point);
    try point_pool.append(point2);
    try point_pool.append(point3);

    const items = point_pool.getItems(&.{.pos});
    _ = items;
}
