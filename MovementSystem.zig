const std = @import("std");
const testing = std.testing;
const Components = @import("../ecs/ComponentRegistry.zig").ComponentName;
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const EntityManager = @import("../ecs/EntityManager.zig").EntityManager;
const Prescient = @import("../ecs/Prescient.zig").Prescient;

const Interface = @import("../ecs/PoolInterface.zig").PoolInterfaceType;

pub const MovementSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator, 
    delta_time: f32 = 0.0,
    queries: struct {
        movement: Query(&.{Components.Position, Components.Velocity}), 
    },

    pub fn update(self: *Self) !void{
        while(try self.queries.movement.next()) |batch| {
            for(batch.Position, batch.Velocity, batch.entities) |pos, vel, entity | {
                _ = entity;
                pos.x += vel.dx;
                pos.y += vel.dy;
            }
        }
    }
};

// test "Basic Movement" {
//     var ent_manager = try EntityManager.init(testing.allocator);
//     defer ent_manager.deinit();
//     var pool_manager = PoolManager.init(testing.allocator); 
//     defer pool_manager.deinit();
//     const movement_pool = try pool_manager.getOrCreatePool(.MovementPool);
//
//     var interface = Interface(.MovementPool).init(movement_pool, &ent_manager);
//
//     _ = try interface.createEntity(.{.Position = .{.x = 0, .y = 0}, .Velocity = .{.dx = 1, .dy = 0}});
//
//     var movement_system = MovementSystem.init(testing.allocator, &pool_manager);
//     defer movement_system.deinit();
//
//     _ = try interface.createEntity(.{.Position = .{.x = 0, .y = 0}, .Velocity = .{.dx = 0, .dy = 1}});
//
//     var iteration: usize = 0;
//     while(true) {
//         iteration += 1;
//         try movement_system.update();
//         pool_manager.flushNewAndReallocatingLists();
//
//         if(iteration >= 5) break; // Exit after 5 iterations for testing
//     }
// }
