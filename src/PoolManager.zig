const std = @import("std");
const PR = @import("PoolRegistry.zig").PoolRegistry;
const PoolEnum = PR.Enum;
const EntPool = @import("EntPool.zig").EntPool;

pub const PoolManager = struct {
    pub const Self = @This();
    const StorageFields = std.meta.fields(PoolStorage);

    allocator: std.mem.Allocator,
    storage: PoolStorage = undefined,

    pub fn init(allocator: std.mem.Allocator) Self {
        var self: Self = .{ .allocator = allocator };
        inline for (StorageFields) |field| {
            @field(self.storage, field.name) = .init(allocator);
        }
        return self;
    }

    pub fn deinit(self: *Self) void {
        inline for (StorageFields) |field| {
            @field(self.storage, field.name).deinit();
        }
    }

    pub fn getPool(self: *Self, comptime pool: PoolEnum) *EntPool(pool) {
        return &@field(self.storage, @tagName(pool));
    }
};

const PoolStorage = PR.Types;
