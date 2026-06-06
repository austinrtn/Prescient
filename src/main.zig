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
//const SparseSetPool = @import("SparseSetPool.zig").SparseSetPool;

pub fn main(init: std.process.Init) !void {
    _ = init;
}

test "sparse set pool" {
    var prescient: *Prescient = try .init(testing.allocator);
    defer prescient.deinit();

    var sparse_set_pool = prescient.getPool(.sparse_set);
    const ent1 = try sparse_set_pool.createEnt(.{ .pos = .{ .x = 1, .y = 1 }, .vel = .{ .xvel = 2, .yvel = 2 } });

    const pos = sparse_set_pool.getComponent(.pos, ent1);
    const vel = sparse_set_pool.getComponent(.vel, ent1);
    try testing.expect(pos.x == 1 and pos.y == 1);
    try testing.expect(vel.xvel == 2 and vel.yvel == 2);

    const ent2 = try prescient.ent.create(.sparse_set, .{ .pos = .{ .x = -1, .y = -1 }, .vel = .{ .xvel = -2, .yvel = -2 } });

    const pos2 = prescient.ent.getComponent(.pos, ent2);
    const vel2 = prescient.ent.getComponent(.vel, ent2);
    try testing.expect(pos2.x == -1 and pos2.y == -1);
    try testing.expect(vel2.xvel == -2 and vel2.yvel == -2);

    try testing.expect(sparse_set_pool.ent_pool.groups.count() == 1);

    // sparse_set_pool.ent_pool.printStorage();
    //sparse_set_pool.ent_pool.printEnts();
    //std.debug.print("_____________________________\n\n", .{});
    try sparse_set_pool.addComponent(.id, 69, ent2);
    // sparse_set_pool.ent_pool.printStorage();
    //sparse_set_pool.ent_pool.printEnts();
    // for (sparse_set_pool.ent_pool.entity_records.items) |record| {
    //     std.debug.print("{any}\n", .{record});
    // }
    const id = sparse_set_pool.getComponent(.id, ent2);
    try testing.expect(id == 69);
}

test "append to pool" {
    var prescient: *Prescient = try .init(testing.allocator);
    defer prescient.deinit();

    var archetype_pool = prescient.getPool(.archetype);
    const ent1 = try archetype_pool.createEnt(.{ .pos = .{ .x = 1, .y = 1 }, .vel = .{ .xvel = 2, .yvel = 2 } });

    const pos = archetype_pool.getComponent(.pos, ent1);
    const vel = archetype_pool.getComponent(.vel, ent1);
    try testing.expect(pos.x == 1 and pos.y == 1);
    try testing.expect(vel.xvel == 2 and vel.yvel == 2);

    const ent2 = try prescient.ent.create(.sparse_set, .{ .pos = .{ .x = -1, .y = -1 }, .vel = .{ .xvel = -2, .yvel = -2 } });

    const pos2 = prescient.ent.getComponent(.pos, ent2);
    const vel2 = prescient.ent.getComponent(.vel, ent2);
    try testing.expect(pos2.x == -1 and pos2.y == -1);
    try testing.expect(vel2.xvel == -2 and vel2.yvel == -2);
    // try archetype_pool.addComponent(.id, 69, ent2);
    try archetype_pool.addComponent(.id, 69, ent2);
}
