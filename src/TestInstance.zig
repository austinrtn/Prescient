const std = @import("std");
const Testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Registry = @import("Registry.zig").Registry;
const PoolInterface = @import("PoolInterface.zig").PoolInterface;
const Prescient = @import("Prescient.zig").Prescient;
const Config = @import("PoolRegistry.zig").PoolRegistry.GetPoolConfig;

const TestPackage = struct {
    prescient: *Prescient,
    arch_pool :PoolInterface(.archetype),
    sparse_pool: PoolInterface(.sparse_set),
    arch_config: type = Config(.archetype),
    sprase_config: type = Config(.sparse_set),
    allocator: Allocator,
    io: Io,
};

pub fn initTestPackage() !TestPackage {
    const prescient: *Prescient = try .init(Testing.allocator);
    const arch_pool = prescient.getPool(.archetype);
    const sparse_pool = prescient.getPool(.sparse_set);
    
    return .{
        .prescient = prescient,
        .arch_pool = arch_pool,
        .sparse_pool = sparse_pool,
        .allocator = Testing.allocator,
        .io = Testing.io,
    };
}