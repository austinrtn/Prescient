const std = @import("std");
const SR = @import("../registries/SystemRegistry.zig");
const PM = @import("PoolManager.zig");

fn SystemManagerStorage(comptime systems: []const SR.SystemName) type {
    var fields:[systems.len]std.builtin.Type.StructField = undefined;

    for(systems, 0..) |system, i| {
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

    return @Type(std.builtin.Type{
        .@"struct" = .{
            .fields = &fields,
            .backing_integer = null,
            .decls = &.{},
            .is_tuple = false,
            .layout = .auto,
        }
    });
}

pub fn SystemManager(comptime systems: []const SR.SystemName) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        storage: SystemManagerStorage(systems),
        pool_manager: *PM.PoolManager,

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PM.PoolManager) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.pool_manager = pool_manager;
            var storage: SystemManagerStorage(systems) = undefined;

            inline for(systems, 0..) |_, i| {
                const SystemType = SR.getTypeByName(systems[i]);
                var sys_instance: SystemType = undefined;

                // Set allocator and active directly (undefined doesn't apply defaults)
                sys_instance.allocator = allocator;
                if (@hasField(SystemType, "active")) {
                    sys_instance.active = true;
                }

                // Initialize all queries via reflection
                inline for(std.meta.fields(@TypeOf(sys_instance.queries))) |field| {
                    @field(sys_instance.queries, field.name) = try field.type.init(allocator, pool_manager);
                }

                @field(storage, @tagName(systems[i])) = sys_instance;
            }
            self.storage = storage;

            return self;
        }

        pub fn initializeSystems(self: *Self) !void {
            inline for(systems) |system| {
                const SystemType = @TypeOf(@field(self.storage, @tagName(system)));
                if (std.meta.hasFn(SystemType, "init")) {
                    var sys = &@field(self.storage, @tagName(system));
                    try sys.init();
                }
            }
        }

        pub fn deinit(self: *Self) void {
            inline for(systems) |system| {
                var system_instance = &@field(self.storage, @tagName(system));
                inline for(std.meta.fields(@TypeOf(system_instance.queries))) |query_field| {
                    @field(system_instance.queries, query_field.name).deinit();
                }
            }
        }

        pub fn deinitializeSystems(self: *Self) void {
            inline for (systems) |system| {
                const SystemType = @TypeOf(@field(self.storage, @tagName(system)));
                if (std.meta.hasFn(SystemType, "deinit")) {
                    var sys = &@field(self.storage, @tagName(system));
                    sys.deinit();
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
            inline for(systems) |system| {
                var sys = &@field(self.storage, @tagName(system));
                // Check if system should run (active field or no active field = always run)
                const should_run = if (@hasField(@TypeOf(sys.*), "active")) sys.active else true;
                if (should_run) {
                    try self.updateSystemQueries(sys);
                    try sys.update();
                }
            }
        }
    };
}
