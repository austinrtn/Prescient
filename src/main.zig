const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Registry = @import("Registry.zig").Registry;
const EntPool = @import("EntPool.zig").EntPool;
const ArchStore = @import("ArchetypeStorage.zig").Archetype;
const Prescient = @import("Prescient.zig").Prescient;
//const Query = @import("Query.zig").Query;
//const SparsePool = @import("SparsePool.zig").SparsePool;

pub fn main(init: std.process.Init) !void {
    _ = init;
}

test "sparse pool" {
    var prescient: *Prescient = try .init(testing.allocator);
    defer prescient.deinit();
    
    var sparse_pool = prescient.getPool(.sparse);
    const ent1 = try sparse_pool.createEnt(.{.pos = .{.x = 1, .y = 1}, .vel = .{.xvel = 2, .yvel = 2}});

    const pos = sparse_pool.getComponent(.pos, ent1);
    const vel = sparse_pool.getComponent(.vel, ent1);
    try testing.expect(pos.x == 1 and pos.y == 1);
    try testing.expect(vel.xvel == 2 and vel.yvel == 2);

    const ent2 = try prescient.ent.create(.sparse, .{.pos = .{.x = -1, .y = -1}, .vel = .{.xvel = -2, .yvel = -2}});
    
    const pos2 = prescient.ent.getComponent(.pos, ent2);
    const vel2 = prescient.ent.getComponent(.vel, ent2);
    try testing.expect(pos2.x == -1 and pos2.y == -1);
    try testing.expect(vel2.xvel == -2 and vel2.yvel == -2);
    
    try testing.expect(sparse_pool.ent_pool.archetypes.count() == 1);
}

test "append to pool" {
    var prescient: *Prescient = try .init(testing.allocator);
    defer prescient.deinit();
    
    var archetype_pool = prescient.getPool(.archetype);
    const ent1 = try archetype_pool.createEnt(.{.pos = .{.x = 1, .y = 1}, .vel = .{.xvel = 2, .yvel = 2}});

    const pos = archetype_pool.getComponent(.pos, ent1);
    const vel = archetype_pool.getComponent(.vel, ent1);
    try testing.expect(pos.x == 1 and pos.y == 1);
    try testing.expect(vel.xvel == 2 and vel.yvel == 2);

    const ent2 = try prescient.ent.create(.archetype, .{.pos = .{.x = -1, .y = -1}, .vel = .{.xvel = -2, .yvel = -2}});
    
    const pos2 = prescient.ent.getComponent(.pos, ent2);
    const vel2 = prescient.ent.getComponent(.vel, ent2);
    try testing.expect(pos2.x == -1 and pos2.y == -1);
    try testing.expect(vel2.xvel == -2 and vel2.yvel == -2);
    
    try testing.expect(archetype_pool.ent_pool.archetypes.count() == 1);
}

test "get component" {
    const gpa = testing.allocator;
    var prescient: *Prescient = try .init(gpa);
    defer prescient.deinit();

    var pool = prescient.getPool(.general);
    const ent1 = try pool.createEnt(.{.pos = .{.x = 1, .y = 1}, .vel = .{.xvel = 2, .yvel = 2}});

    const pos = pool.getComponent(.pos, ent1);
    try testing.expect(pos.x == 1);
    try testing.expect(pos.y == 1);

    const vel = prescient.ent.getComponent(.vel, ent1);
    try testing.expect(vel.xvel == 2);
    try testing.expect(vel.yvel == 2);
}

// test "pool" {
//     const gpa = testing.allocator;
//     var prescient: Prescient = .init(gpa);
//     defer prescient.deinit();

//     const Point = ComponentRegistry.GetTypeOfComponents(
//         &.{.pos, .vel},
//         false
//     );

//     const PointWithId = ComponentRegistry.GetTypeOfComponents(
//         &.{.pos, .vel, .id},
//         false
//     );

//     var point_pool = prescient.getPool(.general);
//     const point: Point = .{.pos = .{.x = 1, .y = 1}, .vel = .{.xvel = 1, .yvel = 1}};
//     const point2: Point = .{.pos = .{.x = -100, .y = -100}, .vel = .{.xvel = -2, .yvel = -2}};
//     const point3: PointWithId = .{.pos = .{.x = 50, .y = 50}, .vel = .{.xvel = 6, .yvel = 7}, .id = 0};

//     _ = try point_pool.createEnt(point);
//     _ = try point_pool.createEnt(point2);
//     _ = try point_pool.createEnt(point3);

//     try testing.expect(point_pool.ent_pool.archetypes.count() == 2);

//     var query: Query(&.{.pos, .vel}) = try .init(gpa, &prescient.pool_manager);
//     defer query.deinit();

//     var ent_count: usize = 0;

//     while(try query.query()) |batch| {
//         for(batch.pos, batch.vel) |*pos, vel| {
//             const start_x = pos.x;
//             pos.x += vel.xvel;
//             pos.y += vel.yvel;

//             if (start_x == point.pos.x) {
//                 try testing.expectEqual(point.pos.x + point.vel.xvel, pos.x);
//                 try testing.expectEqual(point.pos.y + point.vel.yvel, pos.y);
//             } else if (start_x == point2.pos.x) {
//                 try testing.expectEqual(point2.pos.x + point2.vel.xvel, pos.x); 
//                 try testing.expectEqual(point2.pos.y + point2.vel.yvel, pos.y);
//             } else if (start_x == point3.pos.x) {
//                 try testing.expectEqual(point3.pos.x + point3.vel.xvel, pos.x);
//                 try testing.expectEqual(point3.pos.y + point3.vel.yvel, pos.y);
//             }

//             ent_count += 1;
//         }
//     }
//     try testing.expect(ent_count == 3);
// }
