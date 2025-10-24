//! Archetype-based ECS Storage
//!
//! Implements archetype storage for entities with identical component signatures.
//! An archetype stores all entities that have the exact same set of components,
//! enabling efficient cache-friendly iteration over components.
//!
//! Key Design Patterns:
//! - Virtual table pattern for type-erased component arrays
//! - Inline for loops to resolve runtime hashes to compile-time types
//! - Separation of entity addition from component data initialization

const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");

/// Archetype: Storage for entities with identical component signatures.
///
/// Stores all entities that have the exact same set of components.
/// Components are stored in Structure-of-Arrays (SoA) format with one
/// array per component type, enabling efficient iteration.
pub fn Archetype(comptime optimize: bool, comptime ComponentArrayStorage: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        component_mask: CR.ComponentMask,  // Bitmask for fast component queries
        entities: ArrayList(usize),        // Entity IDs
        component_storage: ComponentArrayStorage,  // Component data storage

        /// Initialize an archetype for the given component signature.
        /// Allocates component arrays based on the component mask.
        pub fn init(allocator: std.mem.Allocator, component_mask: CR.ComponentMask, comptime pool_components: []const CR.ComponentName) !Self {
            var storage: ComponentArrayStorage = undefined;

            // Initialize component arrays based on which components this archetype has
            inline for (pool_components) |component| {
                const field_name = @tagName(component);
                const has_component = MM.maskContains(component_mask, MM.Comptime.componentToBit(component));

                if (comptime optimize) {
                    // Optimized: Always initialize, but only allocate if archetype has this component
                    if (has_component) {
                        @field(storage, field_name) = .{
                            .id = @intFromEnum(component),
                            .component_array = .empty,
                        };
                    } else {
                        @field(storage, field_name) = .{
                            .id = @intFromEnum(component),
                            .component_array = .empty,  // Empty but not null - won't be used
                        };
                    }
                } else {
                    // Unoptimized: Allocate pointer only if archetype has this component
                    if (has_component) {
                        const array_ptr = try allocator.create(ArrayList(CR.getTypeByName(component)));
                        array_ptr.* = .empty;
                        @field(storage, field_name) = .{
                            .id = @intFromEnum(component),
                            .component_array = array_ptr,
                        };
                    } else {
                        @field(storage, field_name) = .{
                            .id = @intFromEnum(component),
                            .component_array = null,
                        };
                    }
                }
            }

            return Self {
                .allocator = allocator,
                .component_mask = component_mask,
                .entities = .empty,
                .component_storage = storage,
            };
        }

        /// Add a new entity to this archetype.
        /// Allocates space in all component arrays that this archetype uses.
        pub fn addEntity(self: *Self, entity: usize, comptime pool_components: []const CR.ComponentName) !void {
            try self.entities.append(self.allocator, entity);

            // Add undefined slot to each component array this archetype has
            inline for (pool_components) |component| {
                const field_name = @tagName(component);
                const has_component = MM.maskContains(self.component_mask, MM.Comptime.componentToBit(component));

                if (has_component) {
                    if (comptime optimize) {
                        // Optimized: Direct array access
                        try @field(self.component_storage, field_name).component_array.append(self.allocator, undefined);
                    } else {
                        // Unoptimized: Pointer dereference
                        if (@field(self.component_storage, field_name).component_array) |array_ptr| {
                            try array_ptr.append(self.allocator, undefined);
                        }
                    }
                }
            }
        }

        /// Set component data for an entity.
        /// Uses comptime field access for O(1) performance.
        pub fn setComponent(self: *Self, entity: usize, comptime component: CR.ComponentName, component_data: CR.getTypeByName(component)) void {
            const field_name = @tagName(component);

            if (comptime optimize) {
                // Optimized: Direct array access
                @field(self.component_storage, field_name).component_array.items[entity] = component_data;
            } else {
                // Unoptimized: Pointer dereference
                if (@field(self.component_storage, field_name).component_array) |array_ptr| {
                    array_ptr.items[entity] = component_data;
                }
            }
        }

        /// Get component data for an entity.
        /// Uses comptime field access for O(1) performance.
        pub fn getComponent(self: *Self, entity: usize, comptime component: CR.ComponentName) CR.getTypeByName(component) {
            const field_name = @tagName(component);

            if (comptime optimize) {
                // Optimized: Direct array access
                return @field(self.component_storage, field_name).component_array.items[entity];
            } else {
                // Unoptimized: Pointer dereference
                if (@field(self.component_storage, field_name).component_array) |array_ptr| {
                    return array_ptr.items[entity];
                }
                unreachable; // Component not in archetype
            }
        }

        /// Remove an entity from this archetype.
        /// Uses swap-remove for O(1) deletion, which changes entity indices.
        pub fn removeEntity(self: *Self, entity: usize, comptime pool_components: []const CR.ComponentName) void {
            _ = self.entities.swapRemove(entity);

            // Remove from each component array this archetype has
            inline for (pool_components) |component| {
                const field_name = @tagName(component);
                const has_component = MM.maskContains(self.component_mask, MM.Comptime.componentToBit(component));

                if (has_component) {
                    if (comptime optimize) {
                        // Optimized: Direct array access
                        _ = @field(self.component_storage, field_name).component_array.swapRemove(entity);
                    } else {
                        // Unoptimized: Pointer dereference
                        if (@field(self.component_storage, field_name).component_array) |array_ptr| {
                            _ = array_ptr.swapRemove(entity);
                        }
                    }
                }
            }
        }

        /// Clean up all resources used by this archetype.
        /// Deinitializes all component arrays that were allocated.
        pub fn deinit(self: *Self, comptime pool_components: []const CR.ComponentName) void {
            self.entities.deinit(self.allocator);

            // Clean up component arrays
            inline for (pool_components) |component| {
                const field_name = @tagName(component);
                const has_component = MM.maskContains(self.component_mask, MM.Comptime.componentToBit(component));

                if (has_component) {
                    if (comptime optimize) {
                        // Optimized: Direct array deinit
                        @field(self.component_storage, field_name).component_array.deinit(self.allocator);
                    } else {
                        // Unoptimized: Deinit and free pointer
                        if (@field(self.component_storage, field_name).component_array) |array_ptr| {
                            array_ptr.deinit(self.allocator);
                            self.allocator.destroy(array_ptr);
                        }
                    }
                }
            }
        }

        /// Get component data for an entity with compile-time type safety.
        /// Alias for getComponent for backwards compatibility.
        pub fn getEntityComponentData(self: *Self, entity: usize, comptime component_name: CR.ComponentName) CR.getTypeByName(component_name) {
            return self.getComponent(entity, component_name);
        }
    };
}

// ============================================================================
// TODO: The following code may be obsolete with pool-based storage
// Keeping for reference until pool integration is complete
// ============================================================================

// /// Type-erased interface for component arrays of different types.
// /// Uses a virtual table pattern (function pointers) to call into
// /// concrete ComponentArray instances without knowing their specific type.
// /// This allows storing arrays of different component types in a homogeneous list.
//
// pub const ComponentArrayInterface = struct {
//     ptr: *anyopaque,  // Pointer to concrete ComponentArray instance
//     addEntityFn: *const fn(*anyopaque, std.mem.Allocator, entity: usize) anyerror!void,
//     setComponentFn: *const fn(*anyopaque, entity: usize, component_data: *const anyopaque) void,
//     removeEntityFn: *const fn(*anyopaque, entity: usize) void,
//     deinitFn: *const fn(*anyopaque, std.mem.Allocator) void,
//     name: []const u8,      // Component name for debugging
//     component_id: usize,   // Component enum int for lookup
//
//     /// Add a new entity slot with undefined component data.
//     pub fn addEntity(self: *ComponentArrayInterface, allocator: std.mem.Allocator, entity: usize) anyerror!void {
//         try self.addEntityFn(self.ptr, allocator, entity);
//     }
//
//     /// Set the component data for an entity.
//     pub fn setComponent(self: *ComponentArrayInterface, entity: usize, component_data: *const anyopaque) void {
//         self.setComponentFn(self.ptr, entity, component_data);
//     }
//
//     /// Remove an entity from this component array.
//     pub fn removeEntity(self: *ComponentArrayInterface, entity: usize) void {
//         self.removeEntityFn(self.ptr, entity);
//     }
//
//     /// Clean up this component array and free its memory.
//     pub fn deinit(self: *ComponentArrayInterface, allocator: std.mem.Allocator) void {
//         self.deinitFn(self.ptr, allocator);
//     }
// };
//
// /// Generic component array for a specific component type.
// /// This function returns a new struct type for each unique component type.
// /// The component type is baked into the struct at compile time.
// ///
// /// Note: comp_type is a const declaration, NOT a struct field.
// /// This is crucial because `type` values cannot exist at runtime in Zig.
// /// By making it a const, the type information is available at compile time
// /// but doesn't occupy space in the struct at runtime.
// fn ComponentArray(meta_data: CR.ComponentMetaData) type {
//     return struct {
//         const Self = @This();
//
//         name: []const u8 = meta_data.name,
//         component_id: usize = meta_data.component_id,
//         list: ArrayList(meta_data.comp_type) = .{},
//
//         // Component type available at comptime, not stored in instances
//         const comp_type = meta_data.comp_type;
//
//         /// Add a new entity slot. Component data will be set later via setComponent.
//         /// The entity parameter is currently unused but reserved for future entity ID tracking.
//         pub fn addEntity(self: *Self, allocator: std.mem.Allocator, entity: usize) !void {
//             _ = entity;
//             try self.list.append(allocator, undefined);
//         }
//
//         /// Set component data for an entity by casting from type-erased pointer.
//         /// The entity parameter is used as an index into the component array.
//         pub fn setComponent(self: *Self, entity: usize, component_data: *const anyopaque) void {
//             const typed_data: *const comp_type = @alignCast(@ptrCast(component_data));
//             self.list.items[entity] = typed_data.*;
//         }
//
//         /// Remove an entity using swap-remove for O(1) deletion.
//         /// Warning: This changes entity indices! Needs to be coordinated with entity tracking.
//         pub fn removeEntity(self: *Self, entity: usize) void {
//             _ = self.list.swapRemove(entity);
//         }
//
//         /// Clean up the component list and free the array itself.
//         pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
//             self.list.deinit(allocator);
//             allocator.destroy(self);
//         }
//
//         /// Convert this concrete array to a type-erased interface.
//         /// Creates function pointer bindings to this array's methods.
//         pub fn toInterface(self: *Self) ComponentArrayInterface {
//             return .{
//                 .ptr = @ptrCast(self),
//                 .addEntityFn = @ptrCast(&Self.addEntity),
//                 .setComponentFn = @ptrCast(&Self.setComponent),
//                 .removeEntityFn = @ptrCast(&Self.removeEntity),
//                 .deinitFn = @ptrCast(&Self.deinit),
//                 .name = self.name,
//                 .component_id = self.component_id,
//             };
//         }
//     };
// }

// ============================================================================
// Test: Pool-based component storage
// ============================================================================
// TODO: Update this test for new ArchetypePool API (Archetypes are deprecated)
// Commented out until ArchetypePool API is stable
