const std = @import("std");
const Prescient = @import("ecs/Prescient.zig").Prescient;
const eb = @import("ecs/EntityBuilder.zig").EntityBuilderType;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    var pool = try prescient.getPool(.GeneralPool);
    const ent1 = try pool.createEntity(.{
        .Position = .{.x = 5, .y = 6}, 
        .Velocity = .{.dx = 3, .dy = 0}
    });
    _ = ent1;

    while(true) {
        try prescient.update();        
    }
}

