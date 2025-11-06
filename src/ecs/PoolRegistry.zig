const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const ArchPool = @import("ArchetypePool.zig");
const em = @import("EntityManager.zig");

pub const MovementPool = ArchPool.ArchetypePool(&.{}, &.{.Position, .Velocity});
pub const EnemyPool = ArchPool.ArchetypePool(&.{}, &.{.Position, .Velocity, .Attack});

pub const pool_name = enum(u32) {
    MovementPool,
    EnemyPool,
};

pub const pool_types = [_]type{
    MovementPool,
    EnemyPool,
};

pub fn getPoolFromName(comptime pool: pool_name) type {
    return pool_types[@intFromEnum(pool)];
}

pub fn PoolManager() type {
    const pool_storage_type = blk: {
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

        storage: pool_storage_type, 
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self{
            const storage = blk: {
                var result: pool_storage_type = undefined;
                inline for(std.meta.fields(pool_storage_type)) |field_info| {
                    @field(result, field_info.name) = null;
                }
                break :blk result;
            };
            return .{.allocator = allocator, .storage = storage};
        }
        
        pub fn getOrCreatePool(self: *Self, comptime pool: pool_name) !*getPoolFromName(pool) {
            //Get names of each field for the pool storage
            inline for(std.meta.fields(@TypeOf(self.storage))) |field| {
                //Check if pool name matches field
                if(std.mem.eql(u8, field.name, @tagName(pool))) {
                    if(@field(self.storage, field.name)) |*pool_ptr|{
                        return pool_ptr.*;
                    } 
                    else {
                        const ptr = try self.allocator.create(getPoolFromName(pool));
                        ptr.* = try getPoolFromName(pool).init(self.allocator);
                        @field(self.storage, field.name) = ptr;
                        return ptr;
                    }
                }
            }
            unreachable;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(@TypeOf(self.storage))) |field| {
                const pool = &@field(self.storage, field.name);
                if(pool.*) |result| {
                    result.*.deinit();
                    self.allocator.destroy(result);
                }
            }
        }
    };
}

// test "createPool" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     defer _ = gpa.deinit();
//
//     var pool_manager = PoolManager().init(allocator);
//     defer pool_manager.deinit();
//     const movement = try pool_manager.getOrCreatePool(.MovementPool);
//
//     //const Position = cr.getTypeByName(.Position);
//     const Velocity = cr.getTypeByName(.Velocity);
//
//     const ent = try movement.createEntity(.{
//         .Position = .{ .x = 5.0, .y = 3.0 },
//         .Velocity = Velocity{ .dx = 2.0, .dy = 4.0 },
//     });
//     _ = ent;
//     //_ = movement;
// }
