const std = @import("std");
const Io = std.Io;

const Prescient = @import("Prescient");
const Registry = @import("Registry.zig").Registry;
const EntPool = @import("EntPool.zig").EntPool;
const ArchStore = @import("ArchetypeStorage.zig").Archetype;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const PointPool = EntPool(&.{.pos, .vel, .id});

    var point_pool: PointPool = .init(gpa);
    defer point_pool.deinit();

    const PointArch = ArchStore(&.{.pos, .vel, .id});
    var points: PointArch = .init(gpa);
    defer points.deinit();

    const Point = Registry.Component.GetTypeOfComponents(
        &.{.pos, .vel},
        false
    );

    const point: Point = .{.pos = .{.x = 1, .y = 1}, .vel = .{.xvel = 1, .yvel = 1}};
    const point2: Point = .{.pos = .{.x = -100, .y = -100}, .vel = .{.xvel = -2, .yvel = -2}};

    try point_pool.append(point);

    try points.append(point);
    try points.append(point2);
    const items = points.getFields();

    for(0..20) |_| {
        for(items.pos, items.vel) |*pos, vel| {
            pos.x += vel.xvel;
            pos.y += vel.yvel;
        }
    }

    const items2 = points.getFields();
    for(items2.pos) |pos| {
        std.debug.print("{any}\n", .{pos});
    }

    std.debug.print("mask: {any}\n", .{PointArch.mask});
}
