const std = @import("std");
const Io = std.Io;
const Prescient = @import("Prescient");
pub const State = @import("ComptimeState.zig").State;

pub fn main(init: std.process.Init) !void {
    _ = init;
    
    inline for(std.meta.tags(State.Registry.Components.CompEnum)) |tag| {
        std.debug.print("{s}\n", .{@tagName(tag)});
    }
}
