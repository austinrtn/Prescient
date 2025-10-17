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
    type_hash: u64,
    size: usize,
    alignment: usize,
};

/// Full component metadata including the component type.
/// Can only be used at compile time due to the `type` field.
/// Use `toRuntimeMeta()` to convert to runtime-safe metadata.
pub const ComponentMetaData = struct {
    const Self = @This();

    name: []const u8,
    type_hash: u64,
    size: usize,
    alignment: usize,
    comp_type: type,  // Comptime-only!

    /// Generate metadata for a component at compile time.
    pub fn get(comptime componentName: ComponentName) Self {
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

    /// Convert to runtime-safe metadata by dropping the `type` field.
    pub fn toRuntimeMeta(self: Self) ComponentRuntimeMeta {
        return .{
            .name = self.name,
            .type_hash = self.type_hash,
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
    /// This is the key to bridging compile-time types with runtime hashes.
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

    /// Generate a unique hash for a component type.
    /// Uses the component's string name as the hash input.
    pub fn hashComponentData(comptime componentName: ComponentName) u64 {
        return std.hash.Murmur2_64.hash(@tagName(componentName));
    }

    /// Look up full metadata (including type) for a component by hash at compile time.
    /// Uses inline for to generate code for each possible component type.
    /// @compileError if hash doesn't match any registered component.
    pub fn getMetaData(comptime hash: u64) ComponentMetaData {
        inline for(@typeInfo(ComponentName).@"enum".fields) |field| {
            const component_name: ComponentName = @enumFromInt(field.value);
            const component_hash = hashComponentData(component_name);
            if(hash == component_hash) {
                return ComponentMetaData.get(component_name);
            }
        }
        @compileError("Unknown component hash");
    }

    /// Look up runtime-safe metadata for a component by hash at runtime.
    /// Panics if hash doesn't match any registered component.
    pub fn getRuntimeMeta(hash: u64) ComponentRuntimeMeta {
        for(Self.runtime_meta_table) |meta| {
            if(hash == meta.type_hash) {
                return meta;
            }
        }
        std.debug.panic("Unknown component hash: 0x{x}", .{hash});
    }
};

test "ComponentRegistry hash generation" {
    // Test that hashes are generated consistently and uniquely
    const pos_hash = ComponentRegistry.hashComponentData(.Position);
    const vel_hash = ComponentRegistry.hashComponentData(.Velocity);

    // Hashes should be different
    try std.testing.expect(pos_hash != vel_hash);

    // Hashes should be consistent
    try std.testing.expectEqual(pos_hash, ComponentRegistry.hashComponentData(.Position));
    try std.testing.expectEqual(vel_hash, ComponentRegistry.hashComponentData(.Velocity));
}

test "ComponentRegistry runtime metadata lookup" {
    // Verify the runtime metadata table was generated correctly
    try std.testing.expectEqual(2, ComponentRegistry.runtime_meta_table.len);

    // Test runtime lookup
    const pos_hash = ComponentRegistry.hashComponentData(.Position);
    const vel_hash = ComponentRegistry.hashComponentData(.Velocity);

    const pos_meta = ComponentRegistry.getRuntimeMeta(pos_hash);
    const vel_meta = ComponentRegistry.getRuntimeMeta(vel_hash);

    // Verify Position metadata
    try std.testing.expectEqualStrings("Position", pos_meta.name);
    try std.testing.expectEqual(pos_hash, pos_meta.type_hash);
    try std.testing.expectEqual(@sizeOf(Position), pos_meta.size);

    // Verify Velocity metadata
    try std.testing.expectEqualStrings("Velocity", vel_meta.name);
    try std.testing.expectEqual(vel_hash, vel_meta.type_hash);
    try std.testing.expectEqual(@sizeOf(Velocity), vel_meta.size);

    // Note: Invalid hash test removed - now panics instead of returning null
}

