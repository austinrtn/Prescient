const std = @import("std");

/// Enum of all registered component types.
/// Add new components here and to ComponentTypes array.
pub const ComponentName = enum {

};

/// Array mapping ComponentName enum values to their actual types.
/// Must be kept in sync with ComponentName enum order.
pub const ComponentTypes = [_]type {

};

/// Convert a ComponentName to its corresponding type at compile time.
pub fn getTypeByName(comptime component_name: ComponentName) type{
    const index = @intFromEnum(component_name);
    return ComponentTypes[index];
}
