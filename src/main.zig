const std = @import("std");
const Prescient = @import("ecs/Prescient.zig").Prescient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    var general_pool = try prescient.getPool(.GeneralPool);
    _ = try general_pool.createEntity(.{
        //Components Here
    });

    while(true) {
        try prescient.update();
        break;
    }
}

