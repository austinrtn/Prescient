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
    });
    try prescient.ent.add(ent1, .Velocity, .{.dx = 1, .dy = 0});

    var iter: usize = 0;
    while(true) {
        try prescient.update();        
        std.debug.print("\niter:{}", .{iter});
        iter += 1;
        if(iter == 10) {
            _ = try prescient.ent.hasComponent(ent1, .Velocity);
        }
        if(iter == 100) {
            return;
        }
    }
}

