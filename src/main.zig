const std = @import("std");
const Io = std.Io;
const testing = std.testing;

const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Registry = @import("Registry.zig").Registry;
const EntPool = @import("EntPool.zig").EntPool;
const ArchStore = @import("ArchetypeStorage.zig").Archetype;
const Prescient = @import("Prescient.zig").Prescient;
const Query = @import("Query.zig").Query;

pub fn main(init: std.process.Init) !void {
    _ = init;
}

test "pool" {
    const gpa = testing.allocator;
    var prescient: Prescient = .init(gpa);
    defer prescient.deinit();

    const point_pool = prescient.getPool(.general);
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

    _ = try point_pool.append(point);
    _ = try point_pool.append(point2);
    _ = try point_pool.append(point3);

    try testing.expect(point_pool.archetypes.count() == 2);

    var query: Query(&.{.pos, .vel}) = try .init(gpa, &prescient.pool_manager);
    defer query.deinit();

    var ent_count: usize = 0;

    while(try query.query()) |batch| {
        for(batch.pos, batch.vel) |*pos, vel| {
            const start_x = pos.x;
            pos.x += vel.xvel;
            pos.y += vel.yvel;

            if (start_x == point.pos.x) {
                try testing.expectEqual(point.pos.x + point.vel.xvel, pos.x);
                try testing.expectEqual(point.pos.y + point.vel.yvel, pos.y);
            } else if (start_x == point2.pos.x) {
                try testing.expectEqual(point2.pos.x + point2.vel.xvel, pos.x);
                try testing.expectEqual(point2.pos.y + point2.vel.yvel, pos.y);
            } else if (start_x == point3.pos.x) {
                try testing.expectEqual(point3.pos.x + point3.vel.xvel, pos.x);
                try testing.expectEqual(point3.pos.y + point3.vel.yvel, pos.y);
            }

            ent_count += 1;
        }
    }
    try testing.expect(ent_count == 3);
}

test "id manager" {
    const gpa = testing.allocator;
    var prescient: Prescient = .init(gpa);
    defer prescient.deinit();

   try prescient.createEnt(.general, .{.pos = .{.x = 1, .y = 1}, .vel = .{.xvel = 1, .yvel = 1}});
   std.debug.print("{any}\n", .{prescient.id_manager.slots.items[0]});
}
