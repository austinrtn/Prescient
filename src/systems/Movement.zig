const std = @import("std");
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;

pub const Movement = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    queries: struct {
         movement_query: Query(&.{ .Position, .Velocity }),
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.movement_query.next()) |batch| {
            for(batch.Position, batch.Velocity, batch.entities) |position, velocity, entity| {
                _ = entity;
                position.x += velocity.dx;
                position.y += velocity.dy;
                std.debug.print("\n{any}", .{position});
            }
        }
    }
};
