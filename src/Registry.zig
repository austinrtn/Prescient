const PoolDesc = @import("PoolRegistry.zig").PoolDesc;
const CR = @import("ComponentRegistry.zig");
const ComponentDesc = CR.ComponentDesc;

pub const Registry = struct {
    pub const comp_descs = [_]ComponentDesc{
        .{ .name = "pos", .T = struct { x: f32, y: f32 } },
        .{ .name = "vel", .T = struct { xvel: f32, yvel: f32 } },
        .{ .name = "id", .T = u32 },
        .{ .name = "foo", .T = u32 },
        .{ .name = "bar", .T = u32 },
    };

    pub const PoolDescs = [_]PoolDesc{
        .{
            .name = "archetype",
            .components = &.{ .pos, .vel, .id, .foo,  },
            .storage_strategy = .archetype,
        },
        .{
            .name = "sparse_set",
            .components = &.{ .pos, .vel, .id },
            .storage_strategy = .sparse_set,
        },
    };

    pub const EntityId = TypedIndex(u32, "EntityId");
    pub const GroupIndex = TypedIndex(u32, "GroupIndex");
    pub const MemberIndex = TypedIndex(u32, "MemberIndex");
    pub const RecordIndex = TypedIndex(u32, "RecordIndex");
    pub const ComponentIndex = TypedIndex(u32, "ComponentIndex");
    pub const OperationIndex = TypedIndex(u32, "OperationIndex");
    pub const PendingEntityIndex = TypedIndex(u32, "PendingEntityIndex");

    pub fn TypedIndex(comptime T: type, comptime name: []const u8) type {
        return struct {
            pub const type_name = name;
            pub const ValueType = T;
            val: T,

            pub fn init(val: anytype) @This() {
                switch (@typeInfo(@TypeOf(val))) {
                    .int, .comptime_int => {},
                    else => @compileError("TypedIndex value must be of type int!\n"),
                }
                const casted_val: T = @intCast(val);
                return .{ .val = casted_val };
            }

            pub fn idx(self: @This()) usize {
                return @intCast(self.val);
            }

            pub fn eql(self: @This(), other_val: @This()) bool {
                return self.val == other_val.val;
            }
        };
    }
};
