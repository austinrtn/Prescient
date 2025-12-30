const std = @import("std");
const Prescient = @import("ecs/Prescient.zig").Prescient;
const eb = @import("ecs/EntityBuilder.zig").EntityBuilderType;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    var pool = try prescient.getPool(.GeneralPool);
    const ent1 = try pool.createEntity(.{
        .Position = .{.x = 5, .y = 6}, 
        .Velocity = .{.dx = 3, .dy = 0}
    });

    while(true) {
        try prescient.update();        
        const pos = try prescient.getEntityComponentData(ent1, .Position);
        const x = pos.x;
        std.debug.print("\n{}", .{x});
    }
}

