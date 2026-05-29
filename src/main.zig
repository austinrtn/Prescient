const std = @import("std");
const Io = std.Io;

const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;
const Pools = @import("Registry.zig").Registry.EntPools;
const Registry = @import("Registry.zig").Registry;
const EntPool = @import("EntPool.zig").EntPool;
const ArchStore = @import("ArchetypeStorage.zig").Archetype;
const Prescient = @import("Prescient.zig").Prescient;
const Query = @import("Query.zig").Query;

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
    const point3: PointWithId = .{.pos = .{.x = 50, .y = 50}, .vel = .{.xvel = 6, .yvel = 7}, .id = 0};

    try point_pool.append(point);
    try point_pool.append(point2);
    try point_pool.append(point3);

    var query: Query(&.{.pos, .vel}) = try .init(gpa, &prescient.pool_manager);
    defer query.deinit();

    while(try query.query()) |batch| {
        for(batch.pos, batch.vel) |pos, vel| {
            std.debug.print("Pos: {any} | Vel: {any}\n", .{pos, vel});
        }
    }
    
    while(try query.query()) |batch| {
        for(batch.pos, batch.vel) |*pos, vel| {
            pos.x += vel.xvel;
            pos.y += vel.yvel;
        }
    }
    
    while(try query.query()) |batch| {
        for(batch.pos, batch.vel) |pos, vel| {
            std.debug.print("Pos: {any} | Vel: {any}\n", .{pos, vel});
        }
    }

    // const items = point_pool.getItems(&.{.pos});
    // _ = items;
}
