const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PR = @import("PoolRegistry.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;

pub const PoolConfig = struct {
    name: PR.PoolName,
    req: []const CR.ComponentName,
    opt: []const CR.ComponentName,
};

pub fn SparseSetPool(comptime config: PoolConfig) type {
    const req = if(config.req) |req_comps| req_comps else &.{};
    const opt = if(config.opt) |opt_comps| opt_comps else &.{};
    const name = config.name;
    const pool_components = req ++ opt;

    const POOL_MASK = comptime MaskManager.Comptime.createMask(pool_components);

    return struct {

    };
}
