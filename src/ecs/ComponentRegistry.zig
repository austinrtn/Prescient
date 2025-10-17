const std = @import("std");
const Position = @import("Position.zig").Position;
const Velocity = @import("Velocity.zig").Velocity;

pub const ComponentName = enum(32) {
    Position = 0,
    Velocity = 1,
};

pub const ComponentTypes = [_]type {
    Position,
    Velocity,
};

pub fn getTypeByName(comptime componentName: ComponentName) type{
    const index = @intFromEnum(componentName);
    return ComponentTypes[index];
}

pub const ComponentMetaData = struct {
    const Self = @This();

    name: []const u8,
    type_hash: u64,
    size: usize,
    alignment: usize,
    comp_type: type,

    fn get(comptime componentName: ComponentName) Self {
        const name = @tagName(componentName);
        const hash = ComponentRegistry.hashComponentData(componentName);
        const T = getTypeByName(componentName);
        return .{
            .name = name,
            .type_hash = hash,
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .comp_type = T,
        };
    }
};

pub const ComponentRegistry = struct {
    const Self = @This();
    const meta_data = blk: {
        var componentMetaData:[ComponentTypes.len]ComponentMetaData = undefined;
        for(ComponentTypes, 0..) |T, i| {
            componentMetaData[i] = ComponentMetaData.get(T); 
        }

        break :blk componentMetaData;
    };

    pub fn hashComponentData(comptime componentName: ComponentName) u64 {
        return std.hash.Murmur2_64.hash(@tagName(componentName));
    }

    pub fn getMetaData(hash: u64) ComponentMetaData {
        inline for(Self.meta_data) |data| {
            if(hash == data.type_hash) {
                return data;
            }
        }
        @compileError("Unknown component hash: " ++ std.fmt.formatInt(u64, hash, 16, .lower));
    }
};

