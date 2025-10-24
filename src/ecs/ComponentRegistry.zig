//! Component Registry
//!
//! Central registry for all ECS components in the system. Provides compile-time and
//! runtime access to component metadata through hash-based lookups.
//!
//! Key Features:
//! - Compile-time component type resolution via ComponentName enum
//! - Runtime-safe metadata lookup without exposing `type` fields
//! - Hash-based component identification using Murmur2_64

const std = @import("std");
const Position = @import("../components/Position.zig").Position;
const Velocity = @import("../components/Velocity.zig").Velocity;

/// Enum of all registered component types.
/// Add new components here and to ComponentTypes array.
pub const ComponentName = enum {
    Position,
    Velocity,
};

/// Component bitmask type that automatically scales based on component count.
/// Uses u64 for up to 64 components, u128 for up to 128 components.
pub const ComponentMask = blk: {
    const component_count = @typeInfo(ComponentName).@"enum".fields.len;
    if(component_count <= 16) {
        break :blk u16;
    }
    else if(component_count <= 32) {
        break :blk u32;
    } else if(component_count <= 64) {
       break :blk u64;
    } else if (component_count <= 128) {
        break :blk u128;
    } else {
        @compileError("Component count exceeds 128. Consider using a DynamicBitSet or redesigning component architecture.");
    }
};

/// Array mapping ComponentName enum values to their actual types.
/// Must be kept in sync with ComponentName enum order.
pub const ComponentTypes = [_]type {
    Position,
    Velocity,
};

/// Convert a ComponentName to its corresponding type at compile time.
pub fn getTypeByName(comptime componentName: ComponentName) type{
    const index = @intFromEnum(componentName);
    return ComponentTypes[index];
}

/// Runtime-safe component metadata that can be stored and accessed at runtime.
/// Does NOT contain the `type` field since types are comptime-only in Zig.
/// Used for runtime lookups where type information isn't needed.
pub const ComponentRuntimeMeta = struct {
    name: []const u8,
    component_id: usize,
    size: usize,
    alignment: usize,
};

/// Full component metadata including the component type.
/// Can only be used at compile time due to the `type` field.
/// Use `toRuntimeMeta()` to convert to runtime-safe metadata.
pub const ComponentMetaData = struct {
    const Self = @This();

    name: []const u8,
    component_id: usize,
    size: usize,
    alignment: usize,
    comp_type: type,  // Comptime-only!

    /// Generate metadata for a component at compile time.
    pub fn get(comptime componentName: ComponentName) Self {
        const name = @tagName(componentName);
        const id = @intFromEnum(componentName);
        const T = getTypeByName(componentName);
        return .{
            .name = name,
            .component_id = id,
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .comp_type = T,
        };
    }

    /// Convert to runtime-safe metadata by dropping the `type` field.
    pub fn toRuntimeMeta(self: Self) ComponentRuntimeMeta {
        return .{
            .name = self.name,
            .component_id = self.component_id,
            .size = self.size,
            .alignment = self.alignment,
        };
    }
};

pub const ComponentRegistry = struct {
    const Self = @This();

    /// Runtime-accessible lookup table for component metadata.
    /// Generated at compile time but can be accessed at runtime because
    /// it only contains runtime-safe metadata (no `type` fields).
    /// Indexed directly by component enum integer value.
    pub const runtime_meta_table = blk: {
        const enum_fields = @typeInfo(ComponentName).@"enum".fields;
        var table: [enum_fields.len]ComponentRuntimeMeta = undefined;
        for (enum_fields, 0..) |field, i| {
            const component_name: ComponentName = @enumFromInt(field.value);
            const meta = ComponentMetaData.get(component_name);
            table[i] = meta.toRuntimeMeta();
        }
        break :blk table;
    };

    /// Look up runtime-safe metadata for a component by ID (enum int) at runtime.
    /// Direct array access - O(1) performance.
    pub fn getRuntimeMeta(component_id: usize) ComponentRuntimeMeta {
        return Self.runtime_meta_table[component_id];
    }
};

test "ComponentRegistry component IDs" {
    // Test that component IDs are unique and sequential
    const pos_id = @intFromEnum(ComponentName.Position);
    const vel_id = @intFromEnum(ComponentName.Velocity);

    // IDs should be different
    try std.testing.expect(pos_id != vel_id);

    // IDs should be sequential starting from 0
    try std.testing.expectEqual(0, pos_id);
    try std.testing.expectEqual(1, vel_id);
}

test "ComponentRegistry runtime metadata lookup" {
    // Verify the runtime metadata table was generated correctly
    try std.testing.expectEqual(2, ComponentRegistry.runtime_meta_table.len);

    // Test runtime lookup
    const pos_id = @intFromEnum(ComponentName.Position);
    const vel_id = @intFromEnum(ComponentName.Velocity);

    const pos_meta = ComponentRegistry.getRuntimeMeta(pos_id);
    const vel_meta = ComponentRegistry.getRuntimeMeta(vel_id);

    // Verify Position metadata
    try std.testing.expectEqualStrings("Position", pos_meta.name);
    try std.testing.expectEqual(pos_id, pos_meta.component_id);
    try std.testing.expectEqual(@sizeOf(Position), pos_meta.size);

    // Verify Velocity metadata
    try std.testing.expectEqualStrings("Velocity", vel_meta.name);
    try std.testing.expectEqual(vel_id, vel_meta.component_id);
    try std.testing.expectEqual(@sizeOf(Velocity), vel_meta.size);
}

