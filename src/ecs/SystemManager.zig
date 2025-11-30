const std = @import("std");
const SR = @import("SystemRegistry.zig");
const PM = @import("PoolManager.zig");

const SystemManagerStorage = blk: {
    const system_names = std.meta.tags(SR.SystemName);
    var fields:[SR.SystemTypes.len]std.builtin.Type.StructField = undefined;

    for(system_names, 0..) |system, i| {
        const name = @tagName(system);
        const T = SR.getTypeByName(system);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    break :blk @Type(std.builtin.Type{
        .@"struct" = .{
            .fields = &fields,
            .backing_integer = null,
            .decls = &.{},
            .is_tuple = false,
            .layout = .auto,
        }
    });
};


pub const SystemManager = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    storage: SystemManagerStorage,
    pool_manager: *PM.PoolManager,

    pub fn init(allocator: std.mem.Allocator, pool_manager: *PM.PoolManager) Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.pool_manager = pool_manager;

        var storage: SystemManagerStorage = undefined;
        inline for(std.meta.tags(SR.SystemName)) |system| {
            @field(storage, @tagName(system)) = SR.getTypeByName(system).init(allocator, pool_manager);
        }
        self.storage = storage;

        return self;
    }

    pub fn deinit(self: *Self) void {
        inline for(std.meta.fields(SystemManagerStorage)) |field| {
            @field(self.storage, field.name).deinit();
            
        }
    }

    pub fn getSystem(self: *Self, comptime system: SR.SystemName) *SR.getTypeByName(system) {
        const field_name = @tagName(system);
        return &@field(self.storage, field_name);
    }

    pub fn update(self: *Self) !void {
        inline for(std.meta.fields(SystemManagerStorage)) |field| {
            try @field(self.storage, field.name).update();
        }
    }
};

test "SystemManager getSystem" {
    const allocator = std.testing.allocator;

    var pool_manager = PM.PoolManager.init(allocator);
    defer pool_manager.deinit();

    var system_manager = SystemManager.init(allocator, &pool_manager);
    defer system_manager.deinit();

    // Get system first time - should create it
    const movement = system_manager.getSystem(.Movement);
    _ = movement;

    for(0..5) |_|{
        try system_manager.update();
    }
}
