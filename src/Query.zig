const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PoolManager = @import("PoolManager.zig").PoolManager;
const Component = CR.Enum;

pub fn Query(comptime components: []const Component) type {
    const query_return = QueryReturn(components);
    
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        pool_manager: *PoolManager,
        data_lists: ArrayList(query_return.Type) = .empty,

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PoolManager) Self {
            const self: Self = .{ .allocator = allocator, .pool_manager = pool_manager};
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.data_lists.deinit(self.allocator);
        }
    };
}

fn QueryReturn(comptime components: []const Component) type {
    const QueryReturnT = blk: {
        var names: [components.len][]const u8 = undefined;
        var types: [components.len]type = undefined;
        var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;
    
        for(components, 0..) |comp, i| {
            const T = ArrayList(CR.GetTypeByField(comp));
            names[i] = @tagName(comp);
            types[i] = T;
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

    return struct {
        pub const Type = QueryReturnT;
        
        fn initQueryReturnType(data: QueryReturnT) void {
            inline for(std.meta.fields(QueryReturnT)) |field| {
                @field(data, field.name) = .empty; 
            }
        }

        fn deinit(allocator: std.mem.allocator, data: *QueryReturnT) void {
            inline for(std.meta.fields(QueryReturnT)) |field| {
                @field(data, field.name).deinit(allocator);
            }
        }
    };
}