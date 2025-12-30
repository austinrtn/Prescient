//! SparseSetPool - Sparse Set Storage Strategy for Entity Component System
//!
//! This module implements a sparse set-based storage pool for entities and their components.
//! Unlike archetype-based storage which groups entities by their exact component signature,
//! sparse set storage keeps all entities in contiguous arrays with optional component slots.
//!
//! ## Key Characteristics
//!
//! - **Stable Entity Indices**: Entity storage indices remain constant throughout the entity's
//!   lifetime, regardless of component additions/removals. This enables safe external references.
//!
//! - **O(1) Component Access**: Direct array indexing provides constant-time component lookup.
//!
//! - **Dynamic Component Composition**: Adding/removing components only updates bitmask membership
//!   and component slots - no data movement required.
//!
//! - **Virtual Archetypes**: Entities are grouped by their component bitmask for query optimization.
//!   These "virtual archetypes" are runtime constructs, not separate storage locations.
//!
//! ## Trade-offs vs Archetype Storage
//!
//! Advantages:
//! - Faster component add/remove operations (no entity migration)
//! - Stable storage indices simplify external references
//! - Better for entities with frequently changing component sets
//!
//! Disadvantages:
//! - Higher memory overhead (nullable slots for all pool components per entity)
//! - Less cache-friendly iteration (components may have null gaps)
//! - Query iteration requires null checks or mask filtering
//!
//! ## Usage
//!
//! ```zig
//! const PlayerPool = SparseSetPoolType(.{
//!     .name = .PlayerPool,
//!     .req = &.{ .Position, .Health },      // Required for all entities
//!     .components = &.{ .Velocity, .AI },   // Optional components
//!     .storage_strategy = .SPARSE,
//! });
//!
//! var pool = PlayerPool.init(allocator);
//! defer pool.deinit();
//!
//! // Create entity with required + optional components
//! const result = try pool.addEntity(entity, .{
//!     .Position = .{ .x = 0, .y = 0 },
//!     .Health = .{ .current = 100, .max = 100 },
//!     .Velocity = .{ .dx = 1, .dy = 0 },  // Optional
//! });
//!
//! // Dynamically add/remove components
//! try pool.addComponent(result.storage_index, .AI, .{ .state = .idle });
//! try pool.removeComponent(result.storage_index, .Velocity);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PC = @import("PoolConfig.zig");
const PoolConfig = PC.PoolConfig;
const PoolName = PC.PoolName;
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const Entity = EM.Entity;
const EB = @import("EntityBuilder.zig");
const EntityBuilderType = EB.EntityBuilderType;
const MQ = @import("MigrationQueue.zig");
const MoveDirection = MQ.MoveDirection;
const MigrationQueueType = MQ.MigrationQueueType;
const MigrationEntryType = MQ.MigrationEntryType;
const PoolInterfaceType = @import("PoolInterface.zig").PoolInterfaceType;
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;

/// Maps an entity's storage location to its virtual archetype membership.
///
/// - `bitmask_index`: Index into the pool's `mask_list` array identifying which virtual archetype
///   (component combination) this entity belongs to.
/// - `in_list_index`: Index within that virtual archetype's `storage_indexes` list, enabling
///   O(1) removal via swap-remove when the entity changes archetypes.
const BitmaskMap = struct { bitmask_index: u32, in_list_index: u32 };

/// Generates a struct type for storing entity data in parallel arrays (Structure of Arrays).
///
/// The generated struct contains:
/// - `entities`: ArrayList(?Entity) - Maps storage index to entity handle (null if slot is free)
/// - `bitmask_map`: ArrayList(?BitmaskMap) - Maps storage index to virtual archetype membership
/// - One ArrayList(?T) per component in the pool
///
/// All arrays are indexed by `storage_index`, maintaining parallel alignment.
/// Null values indicate the entity doesn't have that component (or slot is free).
///
/// Example generated struct for components [.Position, .Velocity]:
/// ```zig
/// struct {
///     entities: ArrayList(?Entity),
///     bitmask_map: ArrayList(?BitmaskMap),
///     Position: ArrayList(?PositionType),
///     Velocity: ArrayList(?VelocityType),
/// }
/// ```
fn StorageType(comptime components: []const CR.ComponentName) type {
    const field_count = components.len + 2;
    var fields: [field_count]std.builtin.Type.StructField = undefined;

    // Field 0: Entity handle storage - maps storage_index -> Entity
    fields[0] = .{
        .name = "entities",
        .type = ArrayList(?Entity),
        .alignment = @alignOf(ArrayList(?Entity)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    // Field 1: Bitmask mapping - tracks which virtual archetype each entity belongs to
    fields[1] = .{
        .name = "bitmask_map",
        .type = ArrayList(?BitmaskMap),
        .alignment = @alignOf(ArrayList(?BitmaskMap)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    // Fields 2+: Component arrays - one per component type, all nullable
    for (components, (field_count - components.len)..) |component, i| {
        const name = @tagName(component);
        const comp_type = CR.getTypeByName(component);
        const T = ArrayList(?comp_type);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}
/// Creates a sparse set pool type for the given configuration.
///
/// The sparse set pool stores all entities in flat parallel arrays, with each component
/// stored as an optional value. This differs from archetype storage where entities are
/// grouped and moved based on their component signature.
///
/// ## Parameters
/// - `config`: Pool configuration specifying:
///   - `name`: Unique identifier for this pool (from PoolName enum)
///   - `req`: Required components that ALL entities must have (compile-time enforced)
///   - `components`: Optional components that entities MAY have
///   - `storage_strategy`: Should be .SPARSE for this pool type
///
/// ## Type Constants (available on returned type)
/// - `NAME`: The pool's identifier
/// - `pool_mask`: Bitmask of ALL components (required + optional)
/// - `REQ_MASK`: Bitmask of only required components
/// - `COMPONENTS`: Slice of all component names
/// - `REQ_COMPONENTS`: Slice of required component names
/// - `COMPONENTS_LIST`: Slice of optional component names
/// - `Builder`: Entity builder type for compile-time validated entity creation
pub fn SparseSetPoolType(comptime config: PoolConfig) type {
    const req = if (config.req) |req_comps| req_comps else &.{};
    const components_list = if (config.components) |comp| comp else &.{};

    // Merge required and optional components into single list
    const pool_components = comptime blk: {
        if (req.len == 0 and components_list.len == 0) {
            @compileError("\nPool must contain at least one component!\n");
        }

        if (req.len == 0 and components_list.len > 0) {
            break :blk components_list;
        } else if (req.len > 0 and components_list.len == 0) {
            break :blk req;
        } else {
            break :blk req ++ components_list;
        }
    };

    const POOL_MASK = comptime MaskManager.Comptime.createMask(pool_components);
    const MigrationQueue = MQ.MigrationQueueType(pool_components);

    const Storage = StorageType(pool_components);

    return struct {
        const Self = @This();

        // ===== Type Constants =====
        pub const NAME = config.name;
        pub const pool_mask = POOL_MASK;
        pub const storage_strategy: StorageStrategy = .SPARSE;
        pub const REQ_MASK = MaskManager.Comptime.createMask(req);
        pub const COMPONENTS = pool_components;
        pub const REQ_COMPONENTS = req;
        pub const COMPONENTS_LIST = components_list;
        pub const Builder = EntityBuilderType(req, components_list);

        // ===== Instance Fields =====

        /// Allocator for all dynamic allocations
        allocator: Allocator,

        /// Structure-of-Arrays storage for entities and components.
        /// All arrays are indexed by storage_index and maintain parallel alignment.
        storage: Storage,

        /// Component bitmasks for each virtual archetype.
        /// Parallel with virtual_archetypes - mask_list[i] corresponds to virtual_archetypes[i].
        mask_list: ArrayList(MaskManager.Mask),

        /// Storage indices for each virtual archetype.
        /// Parallel with mask_list - virtual_archetypes[i] contains entity storage indices
        /// for the virtual archetype with mask mask_list[i].
        virtual_archetypes: ArrayList(ArrayList(u32)),

        /// Free list of storage indices available for reuse.
        /// When an entity is removed, its index is pushed here.
        /// New entities pop from this list before extending storage arrays.
        empty_indexes: ArrayList(usize),

        /// Deferred component add/remove operations.
        /// Batches mutations to avoid mid-iteration structural changes.
        /// Call `flushMigrationQueue()` to apply all pending changes.
        migration_queue: MigrationQueue,

        /// Indices of newly created virtual archetypes since last query cache update.
        /// Queries use this to know which archetypes need evaluation.
        new_archetypes: ArrayList(usize),

        // ===== Lifecycle =====

        /// Initializes a new sparse set pool.
        ///
        /// All storage arrays start empty. The allocator is stored for use in
        /// subsequent operations (entity creation, component storage, etc.).
        pub fn init(allocator: Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.mask_list = .{};
            self.virtual_archetypes = .{};
            self.empty_indexes = .{};
            self.migration_queue = MigrationQueue.init(allocator);
            self.new_archetypes = .{};

            // Initialize all storage arrays (entities, bitmask_map, and each component)
            inline for (std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name) = .{};
            }
            return self;
        }

        /// Releases all memory owned by this pool.
        ///
        /// Frees storage arrays, mask registry, empty index list, and migration queue.
        /// The pool should not be used after calling deinit.
        pub fn deinit(self: *Self) void {
            // Free all component storage arrays
            inline for (std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).deinit(self.allocator);
            }
            // Free each virtual archetype's storage_indexes list
            for (self.virtual_archetypes.items) |*varch| {
                varch.deinit(self.allocator);
            }
            self.virtual_archetypes.deinit(self.allocator);
            self.mask_list.deinit(self.allocator);
            self.empty_indexes.deinit(self.allocator);
            self.migration_queue.deinit();
            self.new_archetypes.deinit(self.allocator);
        }

        /// Creates a pool interface for high-level entity operations.
        ///
        /// The interface provides a convenient API that combines pool and entity manager
        /// functionality, handling internal bookkeeping automatically.
        pub fn getInterface(self: *Self, entity_manager: *EM.EntityManager) PoolInterfaceType(NAME) {
            return PoolInterfaceType(NAME).init(self, entity_manager);
        }

        /// Clears the new archetypes list after queries have processed them.
        /// Called by PoolManager after each frame's query cache updates.
        pub fn flushNewAndReallocatingLists(self: *Self) void {
            self.new_archetypes.clearRetainingCapacity();
        }

        // ===== Entity Management =====

        /// Adds an entity to the pool with the specified components.
        ///
        /// The entity is stored at either a reused slot (from a previously removed entity)
        /// or a new slot at the end of the storage arrays. Components are validated at
        /// compile-time via the Builder type.
        ///
        /// ## Parameters
        /// - `entity`: The entity handle to store
        /// - `component_data`: Compile-time struct literal with component values.
        ///   Required components must be provided; optional components may be omitted.
        ///
        /// ## Returns
        /// - `storage_index`: Index into storage arrays where entity data is stored
        /// - `archetype_index`: Index of the virtual archetype this entity belongs to
        ///
        /// ## Errors
        /// Returns error on allocation failure.
        pub fn addEntity(self: *Self, entity: EM.Entity, comptime component_data: Builder) !struct { storage_index: u32, archetype_index: u32 } {
            // Determine which components are being set (compile-time)
            const components = comptime EB.getComponentsFromData(pool_components, Builder, component_data);
            const bitmask = MaskManager.Comptime.createMask(components);

            // Get storage index: reuse empty slot or allocate new one
            const storage_index: u32 = @intCast(self.empty_indexes.pop() orelse blk: {
                // No empty slots - extend all storage arrays
                inline for (std.meta.fields(Storage)) |field| {
                    try @field(self.storage, field.name).append(self.allocator, null);
                }
                break :blk self.storage.entities.items.len - 1;
            });

            // Clear the slot (handles reused slots that may have stale data)
            inline for (std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[storage_index] = null;
            }

            // Store each provided component
            inline for (components) |component| {
                const T = CR.getTypeByName(component);
                const field_value = @field(component_data, @tagName(component));

                // Unwrap optional if the Builder field is optional
                const data = comptime blk: {
                    const field_info = for (std.meta.fields(Builder)) |f| {
                        if (std.mem.eql(u8, f.name, @tagName(component))) break f;
                    } else unreachable;

                    const is_optional = @typeInfo(field_info.type) == .optional;
                    if (is_optional) {
                        break :blk field_value.?;
                    } else {
                        break :blk field_value;
                    }
                };

                // Handle anonymous struct literals by copying fields individually
                const typed_data = if (@TypeOf(data) == T)
                    data
                else blk: {
                    var result: T = undefined;
                    inline for (std.meta.fields(T)) |field| {
                        if (!@hasField(@TypeOf(data), field.name)) {
                            @compileError("Field " ++ field.name ++ " is missing from component " ++
                                @tagName(component) ++ "!\nMake sure fields of all components are included and spelled properly when using Pool.createEntity()\n");
                        }
                        @field(result, field.name) = @field(data, field.name);
                    }
                    break :blk result;
                };

                @field(self.storage, @tagName(component)).items[storage_index] = typed_data;
            }

            // Store entity handle and register with virtual archetype
            self.storage.entities.items[storage_index] = entity;
            const new_bitmask_map = try self.getOrCreateBitmaskMap(bitmask);
            self.storage.bitmask_map.items[storage_index] = new_bitmask_map;

            // Add to virtual archetype's entity list
            const index: usize = @intCast(new_bitmask_map.bitmask_index);
            try self.virtual_archetypes.items[index].append(self.allocator, storage_index);

            return .{
                .storage_index = storage_index,
                .archetype_index = new_bitmask_map.bitmask_index,
            };
        }

        /// Removes an entity from the pool.
        ///
        /// Clears all component data for this entity and adds the storage slot to the
        /// free list for reuse. The entity is also removed from its virtual archetype's
        /// membership list.
        ///
        /// ## Parameters
        /// - `storage_index`: The entity's storage index
        /// - `pool_name`: Expected pool name (validated at runtime)
        ///
        /// ## Errors
        /// - `EntityPoolMismatch`: If pool_name doesn't match this pool
        pub fn removeEntity(self: *Self, storage_index: u32, pool_name: PoolName) !void {
            try validateEntityInPool(pool_name);

            const bitmask_map = self.getBitmaskMap(storage_index);

            // Clear all storage slots for this entity
            inline for (std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[storage_index] = null;
            }

            // Remove from virtual archetype and recycle storage index
            self.removeFromMaskList(bitmask_map);
            try self.empty_indexes.append(self.allocator, storage_index);
        }

        /// Queues a component addition or removal for deferred processing.
        ///
        /// This is the deferred version of component mutation, used when immediate
        /// changes could cause issues (e.g., during iteration). Changes are batched
        /// in the migration queue and applied when `flushMigrationQueue()` is called.
        ///
        /// For sparse set pools, this is less critical than archetype pools since
        /// storage indices are stable. However, it still provides consistent API
        /// behavior and allows batching multiple changes to the same entity.
        ///
        /// ## Parameters
        /// - `entity`: The entity being modified
        /// - `_`: Unused (mask_list_index, kept for API uniformity with archetype pools)
        /// - `pool_name`: Expected pool name (validated at runtime)
        /// - `storage_index`: The entity's storage index
        /// - `is_migrating`: Whether this is part of a cross-pool migration
        /// - `direction`: `.adding` or `.removing`
        /// - `component`: The component to add/remove (compile-time)
        /// - `data`: Component data (required for adding, null for removing)
        ///
        /// ## Errors
        /// - `EntityPoolMismatch`: If pool_name doesn't match
        /// - `NullComponentData`: If adding with null data
        /// - `AddingExistingComponent`: If entity already has the component
        /// - `RemovingNonexistingComponent`: If entity doesn't have the component
        pub fn addOrRemoveComponent(
            self: *Self,
            entity: Entity,
            _: u32, // mask_list_index - unused for SparseSetPool, kept for API uniformity
            pool_name: PoolName,
            storage_index: u32,
            is_migrating: bool,
            comptime direction: MoveDirection,
            comptime component: CR.ComponentName,
            data: ?CR.getTypeByName(component),
        ) !void {
            // Compile-time validation: ensure component exists in this pool
            validateComponentInPool(component);

            // Runtime validation: ensure entity belongs to this pool
            try validateEntityInPool(pool_name);

            // Compile-time check: prevent removing required components
            comptime {
                if (direction == .removing) {
                    for (req) |req_comp| {
                        if (req_comp == component) {
                            @compileError("You can not remove required component " ++
                                @tagName(component) ++ " from pool " ++ @typeName(Self));
                        }
                    }
                }
            }

            // Runtime check: adding requires non-null data
            if (direction == .adding and data == null) {
                std.debug.print("\ncomponent data cannot be null when adding a component!\n", .{});
                return error.NullComponentData;
            }

            const bitmask_map = self.getBitmaskMap(storage_index);
            const entity_mask = self.getBitmask(bitmask_map.bitmask_index);
            const component_bit = MaskManager.Comptime.componentToBit(component);

            if (direction == .adding) {
                // Verify entity doesn't already have this component
                if (MaskManager.maskContains(entity_mask, component_bit)) {
                    return error.AddingExistingComponent;
                }
                const new_mask = MaskManager.Runtime.addComponent(entity_mask, component);

                const component_data = @unionInit(
                    MigrationQueue.Entry.ComponentDataUnion,
                    @tagName(component),
                    data,
                );

                try self.migration_queue.addMigration(
                    entity,
                    storage_index,
                    entity_mask,
                    new_mask,
                    .adding,
                    component_bit,
                    component_data,
                    is_migrating,
                );
            } else if (direction == .removing) {
                // Verify entity has this component
                if (!MaskManager.maskContains(entity_mask, component_bit)) {
                    return error.RemovingNonexistingComponent;
                }
                const new_mask = MaskManager.Runtime.removeComponent(entity_mask, component);

                const component_data = @unionInit(
                    MigrationQueue.Entry.ComponentDataUnion,
                    @tagName(component),
                    null,
                );

                try self.migration_queue.addMigration(
                    entity,
                    storage_index,
                    entity_mask,
                    new_mask,
                    .removing,
                    component_bit,
                    component_data,
                    is_migrating,
                );
            }
        }

        // ===== Immediate Component Operations =====

        /// Immediately adds a component to an entity.
        ///
        /// This is the synchronous version - the component is added immediately
        /// without going through the migration queue. Use this when not iterating
        /// or when immediate changes are safe.
        ///
        /// ## Parameters
        /// - `storage_index`: The entity's storage index
        /// - `component`: Component type to add (compile-time)
        /// - `value`: The component data
        ///
        /// ## Errors
        /// - `EntityAlreadyHasComponent`: If entity already has this component
        pub fn addComponent(self: *Self, storage_index: u32, comptime component: CR.ComponentName, value: CR.getTypeByName(component)) !void {
            const bitmask_map = self.getBitmaskMap(storage_index);
            const old_bitmask = self.getBitmask(bitmask_map.bitmask_index);

            const new_bitmask = MaskManager.Comptime.addComponent(old_bitmask, component);
            const comp_storage = &@field(self.storage, @tagName(component)).items[storage_index];

            if (comp_storage.* != null) return error.EntityAlreadyHasComponent;

            // Update virtual archetype membership
            self.removeFromMaskList(bitmask_map);
            const new_bitmask_map = try self.getOrCreateBitmaskMap(new_bitmask);
            try self.virtual_archetypes.items[new_bitmask_map.bitmask_index].append(self.allocator, storage_index);
            self.storage.bitmask_map.items[storage_index] = new_bitmask_map;

            // Store the component data
            comp_storage.* = value;
        }

        /// Immediately removes a component from an entity.
        ///
        /// This is the synchronous version - the component is removed immediately
        /// without going through the migration queue. Use this when not iterating
        /// or when immediate changes are safe.
        ///
        /// ## Parameters
        /// - `storage_index`: The entity's storage index
        /// - `component`: Component type to remove (compile-time)
        ///
        /// ## Errors
        /// - `EntityDoesNotHaveComponent`: If entity doesn't have this component
        pub fn removeComponent(self: *Self, storage_index: u32, comptime component: CR.ComponentName) !void {
            const bitmask_map = self.getBitmaskMap(storage_index);
            const bitmask = self.getBitmask(bitmask_map.bitmask_index);

            const new_bitmask = MaskManager.Comptime.removeComponent(bitmask, component);
            const comp_storage = &@field(self.storage, @tagName(component)).items[storage_index];

            if (comp_storage.* == null) return error.EntityDoesNotHaveComponent;

            // Update virtual archetype membership
            self.removeFromMaskList(bitmask_map);
            const new_bitmask_map = try self.getOrCreateBitmaskMap(new_bitmask);
            try self.virtual_archetypes.items[new_bitmask_map.bitmask_index].append(self.allocator, storage_index);
            self.storage.bitmask_map.items[storage_index] = new_bitmask_map;

            // Clear the component data
            comp_storage.* = null;
        }

        // ===== Migration Queue =====

        /// Result of a migration operation for sparse set pools.
        ///
        /// Unlike archetype pools, sparse set pools don't need to report swapped
        /// entities because storage indices remain stable during component changes.
        pub const SparseMigrationResult = struct {
            entity: Entity,
            storage_index: u32,
            bitmask_index: u32,
        };

        /// Applies all pending component changes from the migration queue.
        ///
        /// For each entity with queued changes:
        /// 1. Resolves the final component mask by applying all add/remove operations
        /// 2. Updates virtual archetype membership to match the new mask
        /// 3. Applies component data changes in-place
        ///
        /// This batched approach is efficient when multiple components are being
        /// added/removed from the same entity, as the archetype membership is only
        /// updated once with the final mask.
        ///
        /// ## Returns
        /// Slice of migration results (caller owns the memory and must free it).
        /// Each result contains the entity, its storage index, and new archetype index.
        ///
        /// ## Errors
        /// Returns error on allocation failure.
        pub fn flushMigrationQueue(self: *Self) ![]SparseMigrationResult {
            if (self.migration_queue.count() == 0) return &.{};

            var results = ArrayList(SparseMigrationResult){};
            try results.ensureTotalCapacity(self.allocator, self.migration_queue.count());

            var iter = self.migration_queue.iterator();
            while (iter.next()) |kv| {
                const entity = kv.key_ptr.*;
                var entries = kv.value_ptr.*;

                if (entries.items.len == 0) continue;

                const first_entry = entries.items[0];
                const storage_index = first_entry.storage_index;

                // Step 1: Resolve final mask by applying all queued operations
                var final_mask = first_entry.old_mask;
                for (entries.items) |entry| {
                    if (entry.direction == .adding) {
                        final_mask |= entry.component_mask;
                    } else {
                        final_mask &= ~entry.component_mask;
                    }
                }

                // Step 2: Update virtual archetype membership
                const old_bitmask_map = self.getBitmaskMap(storage_index);
                self.removeFromMaskList(old_bitmask_map);

                const new_bitmask_map = try self.getOrCreateBitmaskMap(final_mask);
                try self.virtual_archetypes.items[new_bitmask_map.bitmask_index].append(self.allocator, storage_index);
                self.storage.bitmask_map.items[storage_index] = new_bitmask_map;

                // Step 3: Apply component data changes in-place
                for (entries.items) |entry| {
                    switch (entry.component_data) {
                        inline else => |data, tag| {
                            const comp_storage = &@field(self.storage, @tagName(tag)).items[storage_index];
                            if (entry.direction == .adding) {
                                comp_storage.* = data;
                            } else {
                                comp_storage.* = null;
                            }
                        },
                    }
                }

                try results.append(self.allocator, .{
                    .entity = entity,
                    .storage_index = storage_index,
                    .bitmask_index = new_bitmask_map.bitmask_index,
                });

                // Clean up entry list for this entity
                entries.deinit(self.allocator);
            }

            self.migration_queue.clear();
            return try results.toOwnedSlice(self.allocator);
        }

        // ===== Component Access =====

        /// Returns a mutable pointer to an entity's component data.
        ///
        /// ## Parameters
        /// - `_`: Unused (mask_list_index, kept for API uniformity)
        /// - `storage_index`: The entity's storage index
        /// - `pool_name`: Expected pool name (validated at runtime)
        /// - `component`: Component type to retrieve (compile-time)
        ///
        /// ## Returns
        /// Mutable pointer to the component data, allowing in-place modification.
        ///
        /// ## Errors
        /// - `EntityPoolMismatch`: If pool_name doesn't match
        /// - `EntityDoesNotHaveComponent`: If entity doesn't have this component
        pub fn getComponent(
            self: *Self,
            _: u32, // mask_list_index - unused for SparseSetPool, kept for API uniformity
            storage_index: u32,
            pool_name: PoolName,
            comptime component: CR.ComponentName,
        ) !*CR.getTypeByName(component) {
            validateComponentInPool(component);
            try validateEntityInPool(pool_name);

            const result = &@field(self.storage, @tagName(component)).items[@intCast(storage_index)];
            if (result.*) |*comp_data| {
                return comp_data;
            } else {
                return error.EntityDoesNotHaveComponent;
            }
        }

        // ===== Internal Helpers =====

        /// Retrieves the bitmask map for an entity at the given storage index.
        fn getBitmaskMap(self: *Self, storage_index: u32) BitmaskMap {
            const index: usize = @intCast(storage_index);
            return self.storage.bitmask_map.items[index].?;
        }

        /// Retrieves the component bitmask for a virtual archetype.
        fn getBitmask(self: *Self, bitmask_index: u32) MaskManager.Mask {
            const index: usize = @intCast(bitmask_index);
            return self.mask_list.items[index];
        }

        /// Removes an entity from its virtual archetype's storage_indexes list.
        ///
        /// Uses swap-remove for O(1) removal. When the removed entity wasn't the
        /// last in the list, the swapped entity's in_list_index is updated to
        /// maintain consistency.
        fn removeFromMaskList(self: *Self, bitmask_map: BitmaskMap) void {
            const storage_indexes = &self.virtual_archetypes.items[bitmask_map.bitmask_index];

            // swapRemove: O(1) removal by swapping with last element
            _ = storage_indexes.swapRemove(bitmask_map.in_list_index);

            // Update the swapped entity's in_list_index if we didn't remove the last element
            if (bitmask_map.in_list_index < storage_indexes.items.len) {
                const swapped_storage_index = storage_indexes.items[bitmask_map.in_list_index];
                self.storage.bitmask_map.items[swapped_storage_index].?.in_list_index = bitmask_map.in_list_index;
            }
        }

        /// Finds or creates a virtual archetype for the given component bitmask.
        ///
        /// Returns a BitmaskMap with:
        /// - bitmask_index: The virtual archetype's index in self.mask_list
        /// - in_list_index: The next available slot in that archetype's storage_indexes
        ///
        /// If no archetype exists for this mask, a new one is created and registered
        /// in new_archetypes for query cache invalidation.
        fn getOrCreateBitmaskMap(self: *Self, bitmask: MaskManager.Mask) !BitmaskMap {
            // Search for existing archetype with matching mask
            for (self.mask_list.items, 0..) |mask, i| {
                if (mask == bitmask) {
                    const storage_indexes = self.virtual_archetypes.items[i];
                    return .{
                        .bitmask_index = @intCast(i),
                        .in_list_index = @intCast(storage_indexes.items.len),
                    };
                }
            }

            // Create new virtual archetype (parallel arrays)
            try self.mask_list.append(self.allocator, bitmask);
            try self.virtual_archetypes.append(self.allocator, .{});

            const bitmask_index = self.mask_list.items.len - 1;
            try self.new_archetypes.append(self.allocator, bitmask_index);

            return .{
                .bitmask_index = @intCast(bitmask_index),
                .in_list_index = 0,
            };
        }

        // ===== Validation Helpers =====

        /// Checks if the given pool name matches this pool.
        fn checkIfEntInPool(pool_name: PoolName) bool {
            return pool_name == NAME;
        }

        /// Compile-time validation that all required components are provided.
        fn validateAllRequiredComponents(comptime components: []const CR.ComponentName) void {
            inline for (req) |required_comp| {
                var found = false;
                inline for (components) |provided_comp| {
                    if (required_comp == provided_comp) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    @compileError("Required component '" ++ @tagName(required_comp) ++
                        "' is missing when creating entity in pool " ++ @typeName(Self));
                }
            }
        }

        /// Runtime validation that a component exists in an entity's archetype mask.
        fn validateComponentInArchetype(archetype_mask: MaskManager.Mask, component: CR.ComponentName) !void {
            if (!MaskManager.maskContains(archetype_mask, MaskManager.Runtime.componentToBit(component))) {
                std.debug.print("\nEntity does not have component: {s}\n", .{@tagName(component)});
                return error.ComponentNotInArchetype;
            }
        }

        /// Runtime validation that an entity belongs to this pool.
        fn validateEntityInPool(pool_name: PoolName) !void {
            if (!checkIfEntInPool(pool_name)) {
                std.debug.print("\nEntity assigned pool '{s}' does not match pool: {s}\n", .{ @tagName(pool_name), @tagName(NAME) });
                return error.EntityPoolMismatch;
            }
        }

        /// Compile-time validation that a component exists in this pool.
        fn validateComponentInPool(comptime component: CR.ComponentName) void {
            comptime {
                var found = false;
                for (pool_components) |comp| {
                    if (comp == component) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    @compileError("Component: " ++ @tagName(component) ++ " does not exist in pool: " ++ @typeName(Self));
                }
            }
        }
    };
}

// =============================================================================
// Tests
// =============================================================================

test "Basic - all optional components" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{ .name = .GeneralPool, .components = std.meta.tags(CR.ComponentName), .storage_strategy = .SPARSE });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 3, .generation = 0};
    const result = try pool.addEntity(entity, .{.Health = CR.Health{.current = 100, .max = 200}});

    try pool.addComponent(result.storage_index, .Position, .{.x = 0, .y = 0});
    try pool.addComponent(result.storage_index, .Velocity, .{.dx = 0, .dy = 0});
    try pool.removeComponent(result.storage_index, .Velocity);
    try pool.addComponent(result.storage_index, .Attack, .{.damage = 100, .crit_chance = 2});
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
}

test "Pool with required components only" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .req = &.{.Position, .Health},
        .storage_strategy = .SPARSE,
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity1, .{
        .Position = .{.x = 10, .y = 20},
        .Health = .{.current = 50, .max = 100}
    });

    // Verify we can get the components
    const pos = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    try testing.expectEqual(@as(f32, 10), pos.x);
    try testing.expectEqual(@as(f32, 20), pos.y);

    const health = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    try testing.expectEqual(@as(u32, 50), health.current);
    try testing.expectEqual(@as(u32, 100), health.max);
}

test "Pool with mixed required and optional components" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .req = &.{ .Position },
        .components = &.{ .Velocity, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    // Entity with only required component
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const result1 = try pool.addEntity(entity1, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Entity with required + optional components
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const result2 = try pool.addEntity(entity2, .{
        .Position = .{.x = 10, .y = 10},
        .Velocity = .{.dx = 1, .dy = 2},
        .Health = .{.current = 100, .max = 100}
    });

    // Verify entity1 has Position but not Velocity
    _ = try pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Position);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Velocity));
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Health));

    // Verify entity2 has all components
    _ = try pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Velocity);
    _ = try pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Health);
}

test "Error: adding component that already exists" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Try to add Position again - should error
    try testing.expectError(
        error.EntityAlreadyHasComponent,
        pool.addComponent(result.storage_index, .Position, .{.x = 10, .y = 10})
    );
}

test "Error: removing component that doesn't exist" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Try to remove component entity doesn't have - should error
    try testing.expectError(
        error.EntityDoesNotHaveComponent,
        pool.removeComponent(result.storage_index, .Health)
    );
}

test "Error: getting component that doesn't exist" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 5}
    });

    // Try to get component entity doesn't have - should error
    try testing.expectError(
        error.EntityDoesNotHaveComponent,
        pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity)
    );
}

test "Entity removal and slot reuse" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    // Add three entities
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const entity3 = EM.Entity{.index = 3, .generation = 0};

    const result1 = try pool.addEntity(entity1, .{.Position = .{.x = 1, .y = 1}});
    const result2 = try pool.addEntity(entity2, .{.Position = .{.x = 2, .y = 2}});
    const result3 = try pool.addEntity(entity3, .{.Position = .{.x = 3, .y = 3}});

    try testing.expectEqual(@as(u32, 0), result1.storage_index);
    try testing.expectEqual(@as(u32, 1), result2.storage_index);
    try testing.expectEqual(@as(u32, 2), result3.storage_index);

    // Remove middle entity
    try pool.removeEntity(result2.storage_index, SparsePool.NAME);

    // Verify entity2 is gone
    try testing.expectEqual(@as(?EM.Entity, null), pool.storage.entities.items[result2.storage_index]);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result2.storage_index, SparsePool.NAME, .Position));

    // Verify entity1 and entity3 still exist
    _ = try pool.getComponent(0, result1.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result3.storage_index, SparsePool.NAME, .Position);

    // Add a new entity - should reuse slot 1 (result2's old slot)
    const entity4 = EM.Entity{.index = 4, .generation = 0};
    const result4 = try pool.addEntity(entity4, .{.Position = .{.x = 4, .y = 4}});

    try testing.expectEqual(result2.storage_index, result4.storage_index); // Should reuse the empty slot

    const pos4 = try pool.getComponent(0, result4.storage_index, SparsePool.NAME, .Position);
    try testing.expectEqual(@as(f32, 4), pos4.x);
}

test "Component modification through pointer" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 5, .y = 10},
        .Health = .{.current = 50, .max = 100}
    });

    // Get component and modify it
    const pos = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    pos.x = 100;
    pos.y = 200;

    // Verify changes persisted
    const pos_check = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    try testing.expectEqual(@as(f32, 100), pos_check.x);
    try testing.expectEqual(@as(f32, 200), pos_check.y);

    // Modify health
    const health = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    health.current = 25;

    const health_check = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    try testing.expectEqual(@as(u32, 25), health_check.current);
}

test "Multiple entities with same component set share bitmask" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity, .Health },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    // Create multiple entities with same components
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const entity3 = EM.Entity{.index = 3, .generation = 0};

    const result1 = try pool.addEntity(entity1, .{
        .Position = .{.x = 1, .y = 1},
        .Velocity = .{.dx = 1, .dy = 0}
    });
    const result2 = try pool.addEntity(entity2, .{
        .Position = .{.x = 2, .y = 2},
        .Velocity = .{.dx = 0, .dy = 1}
    });
    const result3 = try pool.addEntity(entity3, .{
        .Position = .{.x = 3, .y = 3},
        .Health = .{.current = 100, .max = 100}
    });

    // Check bitmask maps
    const bm1 = pool.getBitmaskMap(result1.storage_index);
    const bm2 = pool.getBitmaskMap(result2.storage_index);
    const bm3 = pool.getBitmaskMap(result3.storage_index);

    // entity1 and entity2 have same components, should share bitmask_index
    try testing.expectEqual(bm1.bitmask_index, bm2.bitmask_index);

    // entity3 has different components, should have different bitmask_index
    try testing.expect(bm1.bitmask_index != bm3.bitmask_index);

    // Verify the virtual archetype contains both entities
    const storage_indexes = pool.virtual_archetypes.items[bm1.bitmask_index];
    try testing.expect(storage_indexes.items.len >= 2);
}

test "Add and remove components dynamically" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity, .Health, .Attack },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 1, .generation = 0};
    const result = try pool.addEntity(entity, .{
        .Position = .{.x = 0, .y = 0}
    });

    // Track bitmask changes
    const initial_bm = pool.getBitmaskMap(result.storage_index);

    // Add velocity - should change bitmask
    try pool.addComponent(result.storage_index, .Velocity, .{.dx = 5, .dy = 5});
    const after_vel_bm = pool.getBitmaskMap(result.storage_index);
    try testing.expect(initial_bm.bitmask_index != after_vel_bm.bitmask_index);

    // Add health - should change bitmask again
    try pool.addComponent(result.storage_index, .Health, .{.current = 100, .max = 100});
    const after_health_bm = pool.getBitmaskMap(result.storage_index);
    try testing.expect(after_vel_bm.bitmask_index != after_health_bm.bitmask_index);

    // Add attack
    try pool.addComponent(result.storage_index, .Attack, .{.damage = 50, .crit_chance = 10});

    // Verify all components exist
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Attack);

    // Now remove components one by one
    try pool.removeComponent(result.storage_index, .Attack);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result.storage_index, SparsePool.NAME, .Attack));

    try pool.removeComponent(result.storage_index, .Velocity);
    try testing.expectError(error.EntityDoesNotHaveComponent, pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity));

    // Position and Health should still exist
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Position);
    _ = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Health);
}

test "SwapRemove correctly updates bitmask_map indices" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    // Create 3 entities with the same component set (they'll share a mask group)
    const entity1 = EM.Entity{.index = 1, .generation = 0};
    const entity2 = EM.Entity{.index = 2, .generation = 0};
    const entity3 = EM.Entity{.index = 3, .generation = 0};

    const result1 = try pool.addEntity(entity1, .{
        .Position = .{.x = 1, .y = 1},
        .Velocity = .{.dx = 1, .dy = 0}
    });
    const result2 = try pool.addEntity(entity2, .{
        .Position = .{.x = 2, .y = 2},
        .Velocity = .{.dx = 0, .dy = 1}
    });
    const result3 = try pool.addEntity(entity3, .{
        .Position = .{.x = 3, .y = 3},
        .Velocity = .{.dx = 1, .dy = 1}
    });

    // All should share the same bitmask
    const bm1 = pool.getBitmaskMap(result1.storage_index);
    const bm2 = pool.getBitmaskMap(result2.storage_index);
    const bm3 = pool.getBitmaskMap(result3.storage_index);

    try testing.expectEqual(bm1.bitmask_index, bm2.bitmask_index);
    try testing.expectEqual(bm1.bitmask_index, bm3.bitmask_index);

    // Their in_list_index should be 0, 1, 2 respectively
    try testing.expectEqual(@as(u32, 0), bm1.in_list_index);
    try testing.expectEqual(@as(u32, 1), bm2.in_list_index);
    try testing.expectEqual(@as(u32, 2), bm3.in_list_index);

    // Remove the middle entity (result2) - this should swap result3 into result2's position
    try pool.removeEntity(result2.storage_index, SparsePool.NAME);

    // result3 should now have in_list_index of 1 (swapped into result2's old spot)
    const bm3_after = pool.getBitmaskMap(result3.storage_index);
    try testing.expectEqual(@as(u32, 1), bm3_after.in_list_index);

    // result1 should be unchanged
    const bm1_after = pool.getBitmaskMap(result1.storage_index);
    try testing.expectEqual(@as(u32, 0), bm1_after.in_list_index);

    // Verify the storage_indexes list is correct
    const storage_indexes = pool.virtual_archetypes.items[bm1.bitmask_index];
    try testing.expectEqual(@as(usize, 2), storage_indexes.items.len);
    try testing.expectEqual(result1.storage_index, storage_indexes.items[0]);
    try testing.expectEqual(result3.storage_index, storage_indexes.items[1]);
}

test "Migration queue flush" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{
        .name = .GeneralPool,
        .components = &.{ .Position, .Velocity },
        .storage_strategy = .SPARSE
    });
    var pool = try SparsePool.init(allocator);
    defer pool.deinit();

    const entity = EM.Entity{.index = 0, .generation = 0};
    const result = try pool.addEntity(entity, .{.Position = .{.x = 3, .y = 2}});

    // Get mask before adding component
    const bm_before = pool.getBitmaskMap(result.storage_index);
    const mask_before = pool.mask_list.items[bm_before.bitmask_index];

    // Queue a component add via migration queue
    try pool.addOrRemoveComponent(
        entity,
        result.archetype_index,
        SparsePool.NAME,
        result.storage_index,
        false,
        .adding,
        .Velocity,
        .{.dx = 1, .dy = 1}
    );

    // Flush the migration queue
    const results = try pool.flushMigrationQueue();
    defer allocator.free(results);

    // Verify migration result
    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expect(std.meta.eql(results[0].entity, entity));

    // Verify mask changed after flush
    const bm_after = pool.getBitmaskMap(result.storage_index);
    const mask_after = pool.mask_list.items[bm_after.bitmask_index];
    try testing.expect(mask_before != mask_after);

    // Verify component is accessible
    const vel = try pool.getComponent(0, result.storage_index, SparsePool.NAME, .Velocity);
    try testing.expectEqual(@as(f32, 1), vel.dx);
    try testing.expectEqual(@as(f32, 1), vel.dy);
}
