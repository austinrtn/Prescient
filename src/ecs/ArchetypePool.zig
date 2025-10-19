const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const EM = @import("EntityManager.zig");
const Archetype = @import("Archetype.zig").Archetype;
const ArrayList = std.ArrayList;
const Entity = @import("EntityManager.zig").Entity;

fn ArchetypeData(comptime component_names: []const CR.ComponentName) type {
    const arch_fields= blk: {
        var fields: [component_names.len]std.builtin.Type.StructField = undefined;

        for(component_names, 0..) |component, i| {
            const T = CR.getTypeByName(component);
            fields[i] = std.builtin.Type.StructField{
                .name = @tagName(component),
                .type = T,
                .alignment = @alignOf(T),
                .default_value_ptr = null,
                .is_comptime = false,
            };
        }
        break :blk fields;
    };

    return std.builtin.Type.Struct{
        .fields = &arch_fields,
        .backing_integer = null,
        .decls = std.builtin.Type.Declaration(.{}),
        .is_tuple = false,
        .layout = .auto,
    };
}

pub fn ArchetypePool(comptime pool_components: []const CR.ComponentName) type {
    const component_set = blk: {
        var set = std.EnumSet(CR.ComponentName).initEmpty();
        for(pool_components) |component| {
            set.insert(component);
        }
        break :blk set;
    };

    return struct {
        const Self = @This();

        components:[]const CR.ComponentName = &pool_components,
        allocator: std.mem.Allocator,
        archetypes: ArrayList(Archetype) = .{}, 

        pub fn init(allocator: std.mem.Allocator) !Self {
            const self = Self{.allocator = allocator};
            return self;
        }

        pub fn createEntity(self: *Self, comptime components: []const CR.ComponentName, component_data: ArchetypeData(components)) void {
            Self.validateComponents(components);            
        }
        
        pub fn addComponent(self: *Self, entity: Entity, comptime component_names: CR.ComponentName, data: CR.getTypeByName(component_names)) void {
            
        }

        pub fn removeComponent(self: *Self ,component_type: CR.ComponentName) void {
            //Self.archetype.remove()
        }

        pub fn createArchetype(self: *Self) void {

        }

        pub fn validateComponents(comptime components: []const CR.ComponentName) void {
            for(components) |component|{
                Self.validateComponent(component);
            }
        }

        pub fn validateComponent(comptime component: CR.ComponentName) void {
            if(!component_set.contains(component)) {
                @compileError("Component '" ++ @tagName(component) ++ "'is not avaiable in this Archetype Pool.\nEither add component to pool, or remove component from entity.");
            }
        }
    };
}
