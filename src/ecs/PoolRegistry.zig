const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const ArchPool = @import("ArchetypePool.zig");

pub const MovementPool = ArchPool.ArchetypePool(&.{.Position, .Velocity}, true);

pub const pool_types = [_]type{
    MovementPool,
};

pub const PoolManager = blk


