const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const Archetype = @import("Archetype.zig").Archetype;
const ArrayList = std.ArrayList;
const EntityManager = @import("EntityManager.zig").EntitySlot;

pub fn ArchetypePool(comptime component_names: []const CR.ComponentName) type {
    return struct {
        const Self = @This();
        const components = &component_names;
        allocator: std.mem.Allocator,
        archetypes: ArrayList(Archetype) = .{}, 

        pub fn init(allocator: std.mem.Allocator) !Self {
            const self = Self{.allocator};
            return self;
        }
        
        pub fn addComponent(self: *Self, entity_slot: u32, comptime component_type: CR.ComponentName) void {
            
        }

        pub fn removeComponent(self: *Self ,component_type: CR.ComponentName) void {
            //Self.archetype.remove()
        }

        pub fn createArchetype(self: *Self) void {

        }
    };
}
