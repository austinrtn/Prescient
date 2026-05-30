const std = @import("std");
const PoolConfig = @import("Registry.zig").Registry.PoolConfigs;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const PoolEnum = PR.Enum;
const EntPool = @import("EntPool.zig").EntPool;

pub const PoolManager = struct {
    pub const Self = @This();
    const StorageFields = std.meta.fields(PoolStorage);

    allocator: std.mem.Allocator,
    storage: PoolStorage = undefined,

    pub fn init(allocator: std.mem.Allocator) Self {
        var self: Self = .{.allocator = allocator};
        inline for(StorageFields) |field| {
            @field(self.storage, field.name) = .init(allocator);
        }
        return self;
    }

    pub fn deinit(self: *Self) void {
        inline for(StorageFields) |field| {
            @field(self.storage, field.name).deinit();
        }
    }

    pub fn getPool(self: *Self, comptime pool: PoolEnum) *EntPool(PR.getConfigByEnum(pool)) {
        return &@field(self.storage, @tagName(pool));
    }
};

const PoolStorage = blk: {
    var names: [PoolConfig.len][]const u8 = undefined;
    var types: [PoolConfig.len]type = undefined;
    var attrs: [PoolConfig.len]std.builtin.Type.StructField.Attributes = undefined;

    for (PoolConfig, 0..) |config, i| {
        names[i] = config.name;
        types[i] = EntPool(config);
        attrs[i] = .{};
    }

    break :blk @Struct(
        .auto,
        null,
        &names,
        &types,
        &attrs,
    );
};
