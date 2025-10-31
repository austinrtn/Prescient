//! Mask Manager
//!
//! Utilities for creating and manipulating component bitmasks.
//! Provides both compile-time and runtime operations.
const std = @import("std");
const CR = @import("ComponentRegistry.zig");

/// Check if a mask contains all required components.
/// Returns true if mask has all bits set that are in required_mask.
pub fn maskContains(mask: CR.ComponentMask, required_mask: CR.ComponentMask) bool {
    return (mask & required_mask) == required_mask;
}

/// Compile-time mask operations
pub const Comptime = struct {
    /// Create a bitmask from multiple components.
    /// ORs together all component bits into a single mask.
    pub fn createMask(comptime components: []const CR.ComponentName) CR.ComponentMask {
        var mask: CR.ComponentMask = 0;
        inline for (components) |comp| {
            mask |= componentToBit(comp);
        }
        return mask;
    }

    /// Convert a single component to its bitmask representation.
    /// Each component gets a unique bit position based on its enum value.
    pub fn componentToBit(comptime component: CR.ComponentName) CR.ComponentMask {
        const bit_position = @intFromEnum(component);
        return @as(CR.ComponentMask, 1) << @intCast(bit_position);
    }

    /// Add a component to an existing mask
    pub fn addComponent(mask: CR.ComponentMask, comptime component: CR.ComponentName) CR.ComponentMask {
        return mask | componentToBit(component);
    }

    /// Remove a component from an existing mask
    pub fn removeComponent(mask: CR.ComponentMask, comptime component: CR.ComponentName) CR.ComponentMask {
        return mask & ~componentToBit(component);
    }
};

/// Runtime mask operations
pub const Runtime = struct {
    /// Create a bitmask from multiple components at runtime.
    /// ORs together all component bits into a single mask.
    pub fn createMask(components: []const CR.ComponentName) CR.ComponentMask {
        var mask: CR.ComponentMask = 0;
        for (components) |comp| {
            mask |= componentToBit(comp);
        }
        return mask;
    }

    /// Convert a single component to its bitmask representation at runtime.
    /// Each component gets a unique bit position based on its enum value.
    pub fn componentToBit(component: CR.ComponentName) CR.ComponentMask {
        const bit_position = @intFromEnum(component);
        return @as(CR.ComponentMask, 1) << @intCast(bit_position);
    }

    /// Add a component to an existing mask at runtime
    pub fn addComponent(mask: CR.ComponentMask, component: CR.ComponentName) CR.ComponentMask {
        return mask | componentToBit(component);
    }

    /// Remove a component from an existing mask at runtime
    pub fn removeComponent(mask: CR.ComponentMask, component: CR.ComponentName) CR.ComponentMask {
        return mask & ~componentToBit(component);
    }
};
