const std = @import("std");
const Prescient = @import("ecs/Prescient.zig").Prescient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    const prescient = try Prescient.init(allocator);

    var pool = try prescient.getPool(.GeneralPool);
    _ = try pool.createEntity(.{
        .Position = .{.x = 5, .y = 0},
        .Velocity = .{.dx = 1, .dy = 0}, 
    });

    while(true) {
        try prescient.update();
    }
}

