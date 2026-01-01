const std = @import("std");
const SR = @import("../registries/SystemRegistry.zig");
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
        inline for(std.meta.tags(SR.SystemName), 0..) |_, i| {
            const SystemType = SR.SystemTypes[i];
            var sys_instance: SystemType = undefined;

            // Set allocator directly
            sys_instance.allocator = allocator;

            // Initialize all queries via reflection
            inline for(std.meta.fields(@TypeOf(sys_instance.queries))) |field| {
                @field(sys_instance.queries, field.name) = field.type.init(allocator, pool_manager);
            }

            @field(storage, std.meta.fields(SystemManagerStorage)[i].name) = sys_instance;
        }
        self.storage = storage;

        return self;
    }

    pub fn initializeSystems(self: *Self) !void {
        inline for (std.meta.fields(SystemManagerStorage)) |field| {
            const SystemType = @TypeOf(@field(self.storage, field.name));
            if (std.meta.hasFn(SystemType, "init")) {
                var system = &@field(self.storage, field.name);
                try system.init();
            }
        }
    }

    pub fn deinit(self: *Self) void {
        inline for(std.meta.fields(SystemManagerStorage)) |field| {
            var system = &@field(self.storage, field.name);
            inline for(std.meta.fields(@TypeOf(system.queries))) |query_field| {
                @field(system.queries, query_field.name).deinit();
            }
        }
    }

    pub fn deitializeSystems(self: *Self) void {
        inline for (std.meta.fields(SystemManagerStorage)) |field| {
            const SystemType = @TypeOf(@field(self.storage, field.name));
            if (std.meta.hasFn(SystemType, "deinit")) {
                var system = &@field(self.storage, field.name);
                try system.deinit();
            }
        }
    }
    fn updateSystemQueries(self: *Self, system: anytype) !void {
        _ = self;
        inline for(std.meta.fields(@TypeOf(system.queries))) |query_field| {
            try @field(system.queries, query_field.name).update();
        }
    }

    pub fn getSystem(self: *Self, comptime system: SR.SystemName) *SR.getTypeByName(system) {
        const field_name = @tagName(system);
        return &@field(self.storage, field_name);
    }

    pub fn update(self: *Self) !void {
        inline for(std.meta.fields(SystemManagerStorage)) |field| {
            var system = &@field(self.storage, field.name);
            try self.updateSystemQueries(system);
            try system.update();
        }
    }
};
