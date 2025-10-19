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

/// Type-erased interface for component arrays of different types.
/// Uses a virtual table pattern (function pointers) to call into
/// concrete ComponentArray instances without knowing their specific type.
/// This allows storing arrays of different component types in a homogeneous list.

/// Helper to create a consistent signature from unsorted component IDs.
/// Sorts the component IDs to ensure that archetypes with the same components
/// but in different order produce the same signature.
pub const SortedSignature = struct {
    ids: []u64,
    signature: u64,

    pub fn init(allocator: std.mem.Allocator, component_ids: []const u64) !SortedSignature {
        // Duplicate the array so we can sort it
        const sorted_ids = try allocator.dupe(u64, component_ids);
        errdefer allocator.free(sorted_ids);

        // Sort in-place for consistent ordering
        std.mem.sort(u64, sorted_ids, {}, std.sort.asc(u64));

        // Hash the sorted IDs
        const signature = std.hash.Murmur2_64.hash(std.mem.sliceAsBytes(sorted_ids));

        return .{
            .ids = sorted_ids,
            .signature = signature,
        };
    }

    pub fn deinit(self: *SortedSignature, allocator: std.mem.Allocator) void {
        allocator.free(self.ids);
    }
};

pub const ComponentArrayInterface = struct {
    ptr: *anyopaque,  // Pointer to concrete ComponentArray instance
    addEntityFn: *const fn(*anyopaque, std.mem.Allocator, entity: usize) anyerror!void,
    setComponentFn: *const fn(*anyopaque, entity: usize, component_data: *const anyopaque) void,
    removeEntityFn: *const fn(*anyopaque, entity: usize) void,
    deinitFn: *const fn(*anyopaque, std.mem.Allocator) void,
    name: []const u8,  // Component name for debugging
    hash: u64,         // Component hash for lookup

    /// Add a new entity slot with undefined component data.
    pub fn addEntity(self: *ComponentArrayInterface, allocator: std.mem.Allocator, entity: usize) anyerror!void {
        try self.addEntityFn(self.ptr, allocator, entity);
    }

    /// Set the component data for an entity.
    pub fn setComponent(self: *ComponentArrayInterface, entity: usize, component_data: *const anyopaque) void {
        self.setComponentFn(self.ptr, entity, component_data);
    }

    /// Remove an entity from this component array.
    pub fn removeEntity(self: *ComponentArrayInterface, entity: usize) void {
        self.removeEntityFn(self.ptr, entity);
    }

    /// Clean up this component array and free its memory.
    pub fn deinit(self: *ComponentArrayInterface, allocator: std.mem.Allocator) void {
        self.deinitFn(self.ptr, allocator);
    }
};

/// Generic component array for a specific component type.
/// This function returns a new struct type for each unique component type.
/// The component type is baked into the struct at compile time.
///
/// Note: comp_type is a const declaration, NOT a struct field.
/// This is crucial because `type` values cannot exist at runtime in Zig.
/// By making it a const, the type information is available at compile time
/// but doesn't occupy space in the struct at runtime.
fn ComponentArray(meta_data: CR.ComponentMetaData) type {
    return struct {
        const Self = @This();

        name: []const u8 = meta_data.name,
        hash: u64 = meta_data.type_hash,
        list: ArrayList(meta_data.comp_type) = .{},

        // Component type available at comptime, not stored in instances
        const comp_type = meta_data.comp_type;

        /// Add a new entity slot. Component data will be set later via setComponent.
        /// The entity parameter is currently unused but reserved for future entity ID tracking.
        pub fn addEntity(self: *Self, allocator: std.mem.Allocator, entity: usize) !void {
            _ = entity;
            try self.list.append(allocator, undefined);
        }

        /// Set component data for an entity by casting from type-erased pointer.
        /// The entity parameter is used as an index into the component array.
        pub fn setComponent(self: *Self, entity: usize, component_data: *const anyopaque) void {
            const typed_data: *const comp_type = @alignCast(@ptrCast(component_data));
            self.list.items[entity] = typed_data.*;
        }

        /// Remove an entity using swap-remove for O(1) deletion.
        /// Warning: This changes entity indices! Needs to be coordinated with entity tracking.
        pub fn removeEntity(self: *Self, entity: usize) void {
            _ = self.list.swapRemove(entity);
        }

        /// Clean up the component list and free the array itself.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.list.deinit(allocator);
            allocator.destroy(self);
        }

        /// Convert this concrete array to a type-erased interface.
        /// Creates function pointer bindings to this array's methods.
        pub fn toInterface(self: *Self) ComponentArrayInterface {
            return .{
                .ptr = @ptrCast(self),
                .addEntityFn = @ptrCast(&Self.addEntity),
                .setComponentFn = @ptrCast(&Self.setComponent),
                .removeEntityFn = @ptrCast(&Self.removeEntity),
                .deinitFn = @ptrCast(&Self.deinit),
                .name = self.name,
                .hash = self.hash,
            };
        }
    };
}

/// Archetype: Storage for entities with identical component signatures.
///
/// Stores all entities that have the exact same set of components.
/// Components are stored in Structure-of-Arrays (SoA) format with one
/// array per component type, enabling efficient iteration.
pub const Archetype = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    signature: u64,                                  // Hash of component_ids for quick comparison
    component_ids: []const u64,                       // Component hashes defining this archetype
    entities: ArrayList(usize),                       // Entity IDs (indices into component arrays)
    component_arrays: ArrayList(ComponentArrayInterface), // Type-erased component storage

    /// Initialize an archetype for the given component signature.
    ///
    /// The key trick: Uses inline for to match runtime hashes against comptime component types.
    /// When `hash == comp_hash`, the compiler knows comp_name at comptime, allowing
    /// us to instantiate ComponentArray with the concrete type even though we started
    /// with a runtime hash value.
    ///
    /// Panics if any component hash doesn't match a registered component.
    pub fn init(allocator: std.mem.Allocator, component_ids: []const u64) !Self {
        var component_arrays: ArrayList(ComponentArrayInterface) = .empty;
        try component_arrays.ensureTotalCapacity(allocator, component_ids.len);

        // Create sorted signature for consistent archetype identification
        var sorted_sig = try SortedSignature.init(allocator, component_ids);
        errdefer sorted_sig.deinit(allocator);

        // For each runtime hash, find its compile-time component type
        outer: for(component_ids) |hash| {
            // inline for generates separate code for each component type at compile time
            // This allows matching runtime hash to comptime type information
            inline for(@typeInfo(CR.ComponentName).@"enum".fields) |field| {
                const comp_name: CR.ComponentName = @enumFromInt(field.value);
                const comp_hash = comptime CR.ComponentRegistry.hashComponentData(comp_name);

                // When this branch is taken, comp_name is known at compile time!
                if (hash == comp_hash) {
                    const meta_data = CR.ComponentMetaData.get(comp_name);
                    const CompArrayType = ComponentArray(meta_data);

                    // Allocate and initialize the concrete component array
                    var comp_array = try allocator.create(CompArrayType);
                    comp_array.* = .{};

                    // Convert to type-erased interface and store
                    try component_arrays.append(allocator, comp_array.toInterface());
                    continue :outer;
                }
            }
            // If we get here, hash didn't match any registered component
            unreachable; // Unknown component hash in archetype init
        }

        return Self {
            .allocator = allocator,
            .component_ids = sorted_sig.ids,  // Transfer ownership of sorted IDs
            .signature = sorted_sig.signature,
            .entities = .empty,
            .component_arrays = component_arrays,
        };
    }

    /// Add a new entity to this archetype.
    /// Creates undefined slots in all component arrays.
    /// Component data must be set separately using setComponent().
    pub fn addEntity(self: *Self, entity: usize) !void {
        try self.entities.append(self.allocator, entity);
        for(self.component_arrays.items) |*comp_array| {
            try comp_array.addEntity(self.allocator, entity);
        }
    }

    /// Set component data for an entity.
    /// Component type is known at compile time via component_name parameter.
    /// Data is passed through type erasure to the appropriate component array.
    pub fn setComponent(self: *Self, entity: usize, comptime component_name: CR.ComponentName, component_data: CR.getTypeByName(component_name)) void {
        const hash = CR.ComponentRegistry.hashComponentData(component_name);
        for(self.component_arrays.items) |*comp_array| {
            if(hash != comp_array.hash) continue;
            comp_array.setComponent(entity, &component_data);
            break;
        }
    }

    /// Remove an entity from this archetype.
    /// Uses swap-remove for O(1) deletion, which changes entity indices.
    pub fn removeEntity(self: *Self, entity: usize) void {
        _ = self.entities.swapRemove(entity);
        for(self.component_arrays.items) |*comp_array| {
            comp_array.removeEntity(entity);
        }
    }

    /// Clean up all resources used by this archetype.
    /// Calls deinit on all component arrays (which frees their allocations)
    /// then frees the arrays list, entities list, and component_ids.
    pub fn deinit(self: *Self) void {
        for (self.component_arrays.items) |*comp_array| {
            comp_array.deinit(self.allocator);
        }
        self.component_arrays.deinit(self.allocator);
        self.entities.deinit(self.allocator);
        self.allocator.free(self.component_ids);
    }

    /// Get component data for an entity with compile-time type safety.
    /// Returns the actual component value (not a pointer).
    ///
    /// This is safe because:
    /// 1. component_name is comptime, so we know the type at compile time
    /// 2. We cast the interface pointer back to the concrete ComponentArray type
    /// 3. The concrete type's list contains the actual component values
    pub fn getEntityComponentData(self: *Self, entity: usize, comptime component_name: CR.ComponentName) CR.getTypeByName(component_name) {
        const hash = CR.ComponentRegistry.hashComponentData(component_name);
        for(self.component_arrays.items) |component_array| {
            if(hash == component_array.hash) {
                // Cast back to the concrete type to access the typed list
                const CompArrayType = ComponentArray(CR.ComponentMetaData.get(component_name));
                const concrete: *CompArrayType = @alignCast(@ptrCast(component_array.ptr));
                return concrete.list.items[entity];
            }
        }
        unreachable; // Component not found in archetype
    }
};

test "Archetype basic operations" {
    const Position = @import("../components/Position.zig").Position;
    const Velocity = @import("../components/Velocity.zig").Velocity;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create archetype with runtime hashes
    const pos_hash = CR.ComponentRegistry.hashComponentData(.Position);
    const vel_hash = CR.ComponentRegistry.hashComponentData(.Velocity);
    const component_ids = [_]u64{ pos_hash, vel_hash };

    var archetype = try Archetype.init(allocator, &component_ids);
    defer archetype.deinit();

    // Add entities
    try archetype.addEntity(0);
    try archetype.addEntity(1);
    try archetype.addEntity(2);

    // Set component data for entity 0
    archetype.setComponent(0, .Position, Position{ .x = 10.0, .y = 20.0 });
    archetype.setComponent(0, .Velocity, Velocity{ .dx = 1.0, .dy = 2.0 });

    // Set component data for entity 1
    archetype.setComponent(1, .Position, Position{ .x = 30.0, .y = 40.0 });
    archetype.setComponent(1, .Velocity, Velocity{ .dx = 3.0, .dy = 4.0 });

    // Set component data for entity 2
    archetype.setComponent(2, .Position, Position{ .x = 50.0, .y = 60.0 });
    archetype.setComponent(2, .Velocity, Velocity{ .dx = 5.0, .dy = 6.0 });

    // Verify entity 0 data
    const pos0 = archetype.getEntityComponentData(0, .Position);
    const vel0 = archetype.getEntityComponentData(0, .Velocity);
    try std.testing.expectEqual(10.0, pos0.x);
    try std.testing.expectEqual(20.0, pos0.y);
    try std.testing.expectEqual(1.0, vel0.dx);
    try std.testing.expectEqual(2.0, vel0.dy);

    // Verify entity 1 data
    const pos1 = archetype.getEntityComponentData(1, .Position);
    const vel1 = archetype.getEntityComponentData(1, .Velocity);
    try std.testing.expectEqual(30.0, pos1.x);
    try std.testing.expectEqual(40.0, pos1.y);
    try std.testing.expectEqual(3.0, vel1.dx);
    try std.testing.expectEqual(4.0, vel1.dy);

    // Verify entity 2 data
    const pos2 = archetype.getEntityComponentData(2, .Position);
    const vel2 = archetype.getEntityComponentData(2, .Velocity);
    try std.testing.expectEqual(50.0, pos2.x);
    try std.testing.expectEqual(60.0, pos2.y);
    try std.testing.expectEqual(5.0, vel2.dx);
    try std.testing.expectEqual(6.0, vel2.dy);

    // Test entity count
    try std.testing.expectEqual(3, archetype.entities.items.len);

    // Remove entity 1
    archetype.removeEntity(1);
    try std.testing.expectEqual(2, archetype.entities.items.len);
}
