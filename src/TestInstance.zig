const std = @import("std");
const Testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Registry = @import("Registry.zig").Registry;
const PoolInterface = @import("PoolInterface.zig").PoolInterface;
const Prescient = @import("Prescient.zig").Prescient;

const TestPackage = struct {
    *Prescient,
    PoolInterface(.archetype),
    PoolInterface(.sparse_set),
    Allocator,
    Io,
};

pub fn GetPkg() !TestPackage {
    const prescient: *Prescient = try .init(Testing.allocator);
    const arch_pool = prescient.getPool(.archetype);
    const sparse_pool = prescient.getPool(.sparse_set);
    
    return .{
        prescient,
        arch_pool,
        sparse_pool,
        Testing.allocator,
        Testing.io,
    };
}