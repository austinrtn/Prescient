const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const ArchPool = @import("ArchetypePool.zig");

pub const MovementPool = ArchPool.ArchetypePool(&.{.Position, .Velocity}, true);

pub const pool_name = enum(u32) {
    MovementPool,
};

pub const pool_types = [_]type{
    MovementPool,
};

pub fn getPoolFromName(comptime pool: pool_name) type {
    return pool_types[@intFromEnum(pool)];
}

pub fn PoolManager() type {
    const pool_storage = blk: {
        var fields: [pool_types.len]std.builtin.Type.StructField = undefined;
       
        for(pool_types, 0..) |pool, i| {
            const name = @tagName(@as(pool_name,@enumFromInt(i)));
            fields[i] = std.builtin.Type.StructField{
                .name = name,
                .type = ?*pool,
                .alignment = @alignOf(?*pool),
                .default_value_ptr = null,
                .is_comptime = false,
            };
        }

        break :blk @Type(.{
            .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    };

    return struct {
        const Self = @This();
        storage: pool_storage = undefined, 
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self{
            var self: Self = .{.allocator = allocator};
            inline for(std.meta.fieldNames(@TypeOf(self.storage))) |field| {
                @field(self.storage, field) = null;
            }
            return self;
        }
        
        pub fn getOrCreatePool(self: *Self, comptime pool: pool_name) !*getPoolFromName(pool) {
            //Get names of each field for the pool storage
            inline for(std.meta.fieldNames(@TypeOf(self.storage))) |field| {
                //Check if pool name matches field
                if(!std.mem.eql(u8, field, @tagName(pool))) continue;

                if(@field(self.storage, field)) |pool_ptr|{
                    return pool_ptr;
                } 
                else {
                    const ptr = try self.allocator.create(getPoolFromName(pool));
                    ptr.* = getPoolFromName(pool).init(self.allocator);
                    return &ptr;
                }
            }
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fieldNames(@TypeOf(self.storage))) |field| {
                const pool = &@field(self.storage, field);
                pool.*.deinit();
                self.allocator.destroy(pool);
            }
        }
    };
}

test "createPool" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();


}
