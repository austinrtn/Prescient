const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    
    // Skip executable name
    _ = args.next();

    // Get project directory (passed from build.zig)
    const project_dir = args.next() orelse {
        std.debug.print("\nError: No project directory provided.\n", .{});
        std.debug.print("Usage: zig build component -- <ComponentName>\n", .{});
        return;
    };

    // Get component name from user
    const component_name = args.next() orelse {
        std.debug.print("\nError: No component name provided.\n", .{});
        std.debug.print("Usage: zig build component -- <ComponentName>\n", .{});
        return;
    };

    // Build paths
    const components_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "components" });
    defer allocator.free(components_dir);

    const file_name = try std.mem.concat(allocator, u8, &.{ component_name, ".zig" });
    defer allocator.free(file_name);

    const file_path = try std.fs.path.join(allocator, &.{ components_dir, file_name });
    defer allocator.free(file_path);

    // Create components directory if it doesn't exist
    std.fs.cwd().makePath(components_dir) catch {};

    // Check if file already exists
    if (std.fs.cwd().access(file_path, .{})) |_| {
        std.debug.print("\nError: Component '{s}' already exists at {s}\n", .{ component_name, file_path });
        return;
    } else |_| {}

    // Generate component template
    const template = try std.fmt.allocPrint(allocator,
        \\const Prescient = @import("../ecs/Prescient.zig").Prescient;
        \\
        \\pub const {s} = struct {{
        \\    // Add your fields here
        \\    example_field: u32 = 0,
        \\}};
        \\
    , .{component_name});
    defer allocator.free(template);

    // Write the file
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(template);

    std.debug.print("\nComponent created: {s}\n", .{component_name});
    std.debug.print("{s}\n", .{file_path});
    std.debug.print("\nRun 'zig build registry' to regenerate ComponentRegistry.zig\n\n", .{});
}
