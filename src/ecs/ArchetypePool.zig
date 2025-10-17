const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const Archetype = @import("Archetype.zig").Archetype;
const ArrayList = std.ArrayList;

pub fn ArchetypePool(comptime component_names: []const CR.ComponentName) type {
    return struct {
        const Self = @This();
        const components = &component_names;
        var archetypes = ArrayList(Archetype); 
        
        pub fn AddComponent(component_type) {
            Self.archetype.add()
        }

        pub fn RemoveComponent(component_type) {
            Self.archetype.remove()
        }
    };
}
