//! Mask Manager
//!
//! Utilities for creating and manipulating component bitmasks.
//! Provides both compile-time and runtime operations.
const std = @import("std");
const CR = @import("../registries/ComponentRegistry.zig");

pub fn MaskManagerType(comptime COMPONENTS: []const CR.ComponentName) type {
    const MaskType = comptime blk: {
        const len = (COMPONENTS.len);

        if(len <= 8) { break :blk u8; } 
        else if(len <= 16) { break :blk u16; }
        else if(len <= 32) { break :blk u32; }
        else if(len <= 64) { break :blk u64; }
        else if(len <= 128) { break :blk u128; }
    };

    return struct {
        pub const Mask = MaskType;
        const Self = @This();

        pub fn maskContains(mask: Mask, required_mask: Mask) bool {
            return (mask & required_mask) == required_mask;
        }

        pub const Comptime = struct {
            pub fn createMask(comptime components: []const CR.ComponentName) Mask {
                var mask: Mask = 0;
                inline for (components) |component| {
                    mask |= Self.Comptime.componentToBit(component);
                }
                return mask;
            }

            pub fn componentToBit(comptime component: CR.ComponentName) Mask {
                // Use enum index directly as bit position
                const bit_pos = @intFromEnum(component);
                return @as(Mask, 1) << @intCast(bit_pos);
            }

            pub fn addComponent(mask: Mask, comptime component: CR.ComponentName) Mask {
                return mask | Self.Comptime.componentToBit(component);
            }

            pub fn removeComponent(mask: Mask, comptime component: CR.ComponentName) Mask {
                return mask & ~Self.Comptime.componentToBit(component);
            }
        };

        pub const Runtime = struct {
            pub fn createMask(components: []const CR.ComponentName) Mask {
                var mask: Mask = 0;
                for(components) |component| {
                    mask |= Self.Runtime.componentToBit(component);
                }
                return mask;
            }

            pub fn componentToBit(component: CR.ComponentName) Mask {
                // Use enum index directly as bit position
                const bit_pos = @intFromEnum(component);
                return @as(Mask, 1) << @intCast(bit_pos);
            }

            pub fn addComponent(mask: Mask, component: CR.ComponentName) Mask {
                return mask | Self.Runtime.componentToBit(component);
            }

            pub fn removeComponent(mask: Mask, component: CR.ComponentName) Mask {
                return mask & ~Self.Runtime.componentToBit(component);
            }
        };
    };
}

pub const GlobalMaskManager = MaskManagerType(std.enums.values(CR.ComponentName));
