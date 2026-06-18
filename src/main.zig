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
    inline for(std.meta.tags(@TypeOf(sparse_set_pool).PoolComponent)) |comp| {
        std.debug.print("{s}\n", .{@tagName(comp)});
    }
    const ent1 = try sparse_set_pool.createEnt(.{ .pos = .{ .x = 1, .y = 1 }, .vel = .{ .xvel = 2, .yvel = 2 }});

    const pos = sparse_set_pool.getComponent(ent1, .pos);
    const vel = sparse_set_pool.getComponent(ent1, .vel);
    try testing.expect(pos.x == 1 and pos.y == 1);
    try testing.expect(vel.xvel == 2 and vel.yvel == 2);

    const ent2 = try prescient.ent.create(.sparse_set, .{ .pos = .{ .x = -1, .y = -1 }, .vel = .{ .xvel = -2, .yvel = -2 } });

    const pos2 = prescient.ent.getComponent(ent2, .pos);
    const vel2 = prescient.ent.getComponent(ent2, .vel);
    try testing.expect(pos2.x == -1 and pos2.y == -1);
    try testing.expect(vel2.xvel == -2 and vel2.yvel == -2);

    try testing.expect(sparse_set_pool.ent_pool.groups.count() == 1);

    try sparse_set_pool.addComponent(ent2, .id, 65);
    sparse_set_pool.setComponent(ent2, .id, 69);
    const id = sparse_set_pool.getComponent(ent2, .id);
    try testing.expect(id == 69);


    var comps = sparse_set_pool.getComponents(ent1, &.{.pos, .vel});
    comps.pos.x += 1;
    comps.vel.yvel += 1;
    sparse_set_pool.setComponents(ent1, comps);
    
    try testing.expect(comps.pos.x == 2);
    try testing.expect(comps.vel.yvel == 3);
    
    try sparse_set_pool.deleteEnt(ent2);
}

// test "archetype pool" {
//     var prescient: *Prescient = try .init(testing.allocator);
//     defer prescient.deinit();

//     var archetype_pool = prescient.getPool(.archetype);
//     const ent1 = try archetype_pool.createEnt(.{ .pos = .{ .x = 1, .y = 1 }, .vel = .{ .xvel = 2, .yvel = 2 } });

//     const pos = archetype_pool.getComponent(ent1, .pos);
//     const vel = archetype_pool.getComponent(ent1, .vel);
//     try testing.expect(pos.x == 1 and pos.y == 1);
//     try testing.expect(vel.xvel == 2 and vel.yvel == 2);

//     const ent2 = try prescient.ent.create(.archetype, .{ .pos = .{ .x = -1, .y = -1 }, .vel = .{ .xvel = -2, .yvel = -2 } });

//     const pos2 = prescient.ent.getComponent(ent2, .pos);
//     const vel2 = prescient.ent.getComponent(ent2, .vel);
//     try testing.expect(pos2.x == -1 and pos2.y == -1);
//     try testing.expect(vel2.xvel == -2 and vel2.yvel == -2);
    
//     try archetype_pool.addComponent(ent2, .id, 65);
//     archetype_pool.setComponent(ent2, .id, 69);
    
//     const id = archetype_pool.getComponent(ent2, .id);
//     try testing.expect(id == 69);
//     try archetype_pool.deleteEnt(ent2);
// }
