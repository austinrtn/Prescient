//! Entity Builder
//!
//! Generates typed struct builders for creating entities with specific component sets.
//! Required components become non-optional fields, while optional components become
//! nullable fields with default null values.
//!
//! This provides better IDE support (tooltips, autocomplete) compared to anytype
//! while maintaining ergonomic entity creation syntax.

const std = @import("std");
const CR = @import("ComponentRegistry.zig");

/// Generate an EntityBuilder struct type for a specific component configuration
///
/// Required components will be non-optional fields (must be provided)
/// Optional components will be nullable fields with null defaults (can be omitted)
///
/// Example:
/// ```zig
/// const Builder = EntityBuilderType(&.{.Position}, &.{.Health, .Velocity});
/// // Generates:
/// // struct {
/// //     Position: Position,           // Required - must provide
/// //     Health: ?Health = null,       // Optional - can omit
/// //     Velocity: ?Velocity = null,   // Optional - can omit
/// // }
/// ```
pub fn EntityBuilderType(comptime required: []const CR.ComponentName, comptime optional: []const CR.ComponentName) type {
    return comptime blk: {
        var fields: [required.len + optional.len]std.builtin.Type.StructField = undefined;
        var idx: usize = 0;

        // Add required components as non-optional fields
        for (required) |comp| {
            const CompType = CR.getTypeByName(comp);
            fields[idx] = .{
                .name = @tagName(comp),
                .type = CompType,
                .alignment = @alignOf(CompType),
                .is_comptime = false,
                .default_value_ptr = null, // No default - must be provided
            };
            idx += 1;
        }

        // Add optional components as nullable fields with null default
        for (optional) |comp| {
            const CompType = CR.getTypeByName(comp);
            const OptionalType = ?CompType;
            const default_null: OptionalType = null;

            fields[idx] = .{
                .name = @tagName(comp),
                .type = OptionalType,
                .alignment = @alignOf(OptionalType),
                .is_comptime = false,
                .default_value_ptr = &default_null,
            };
            idx += 1;
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
}

test "EntityBuilderType with required and optional fields" {
    const testing = std.testing;

    // Create a builder with Position required, Velocity and Health optional
    const Builder = EntityBuilderType(&.{.Position}, &.{.Velocity, .Health});

    // Test 1: Provide only required field
    const entity1: Builder = .{
        .Position = .{ .x = 10.0, .y = 20.0 },
    };
    try testing.expect(entity1.Position.x == 10.0);
    try testing.expect(entity1.Velocity == null);
    try testing.expect(entity1.Health == null);

    // Test 2: Provide required + one optional
    const entity2: Builder = .{
        .Position = .{ .x = 5.0, .y = 15.0 },
        .Velocity = .{ .dx = 1.0, .dy = 2.0 },
    };
    try testing.expect(entity2.Position.x == 5.0);
    try testing.expect(entity2.Velocity != null);
    try testing.expect(entity2.Velocity.?.dx == 1.0);
    try testing.expect(entity2.Health == null);

    // Test 3: Provide all fields
    const entity3: Builder = .{
        .Position = .{ .x = 1.0, .y = 2.0 },
        .Velocity = .{ .dx = 3.0, .dy = 4.0 },
        .Health = .{ .current = 100.0, .max = 100.0 },
    };
    try testing.expect(entity3.Position.x == 1.0);
    try testing.expect(entity3.Velocity != null);
    try testing.expect(entity3.Health != null);
    try testing.expect(entity3.Health.?.current == 100.0);
}
