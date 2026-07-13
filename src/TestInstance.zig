const std = @import("std");
const Testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Prescient = @import("Prescient.zig").Prescient;

const TestPackage = struct {
    allocator: std.mem.Alloctor,
    io: std.Io,
    prescient: *Prescient,
};

pub fn GetPkg() TestPackage {
    const prescient: *Prescient = .init(Testing.allocator);
    return .{
        .allocator = Testing.allocator,
        .io = Testing.io,
        .prescient = prescient,
    };
}