//! Entity Builder
//!
//! Generates typed struct builders for creating entities with specific component sets.
//! Required components become non-optional fields, while optional components become
//! nullable fields with default null values.
//!
//! This provides better IDE support (tooltips, autocomplete) compared to anytype
//! while maintaining ergonomic entity creation syntax.

const std = @import("std");
const CR = @import("../registries/ComponentRegistry.zig");

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

pub fn getComponentsFromData(comptime pool_components: []const CR.ComponentName, 
    comptime builder: type, 
    comptime component_data: builder) [] const CR.ComponentName {

    const components = comptime blk: {
        var component_list: [pool_components.len]CR.ComponentName = undefined;
        var count: usize = 0;

        // Check all pool components directly (no need for stringToEnum)
        // Note: Builder is generated from this pool's req + components, so all fields are valid
        for (pool_components) |comp| {
            const field_name = @tagName(comp);
            const field_info = for (std.meta.fields(builder)) |f| {
                if (std.mem.eql(u8, f.name, field_name)) break f;
            } else @compileError("Component in pool not found in Builder");

            // Check if this field is optional
            const is_optional = @typeInfo(field_info.type) == .optional;
            const field_value = @field(component_data, field_name);

            // Include if: required field OR optional field with non-null value
            const should_include = !is_optional or (field_value != null);

            if (should_include) {
                component_list[count] = comp;
                count += 1;
            }
        }

        break :blk component_list[0..count].*;
    };

    return &components;
}
