// Migration System:
// Uses HashMap<Entity, ArrayList(MigrationEntry)> to handle cascading migrations.
// When multiple add/removes happen to the same entity within a frame:
// - is_migrating flag on EntitySlot enables O(1) check before hashmap lookup
// - All migrations for an entity are collected in a list
// - On flush: resolve final mask, single move, then set all new component data
// This prevents stale archetype_index bugs and ensures one move per entity per flush.

const std = @import("std");
const CR = @import("../registries/ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PC = @import("../registries/PoolRegistry.zig");
const PoolConfig = PC.PoolConfig;
const PoolName = PC.PoolName;
const PoolInterfaceType = @import("PoolInterface.zig").PoolInterfaceType;
const EB = @import("EntityBuilder.zig");
const EntityBuilderType = EB.EntityBuilderType;
const MaskManager = MM.GlobalMaskManager;
const MQ = @import("MigrationQueue.zig");
const MoveDirection = MQ.MoveDirection;
const MigrationResult = MQ.MigrationResult;
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;
const EOQ = @import("EntityOperationQueue.zig");
const EntityOperationType = EOQ.EntityOperationType;
const EntityOperationResult = EOQ.EntityOperationResult;

const ArrayList = std.ArrayList;
const Entity = EM.Entity;

fn ComponentArrayStorageType(comptime pool_components: []const CR.ComponentName) type {
    var fields: [pool_components.len + 3]std.builtin.Type.StructField = undefined;
    //~Field:index: usize
    fields[0] = std.builtin.Type.StructField{
        .name = "index",
        .type = usize,
        .alignment = @alignOf(usize),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:reallocating: bool
    fields[1] = std.builtin.Type.StructField{
        .name = "reallocating",
        .type = bool,
        .alignment = @alignOf(bool),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:entities: AL(Entity)
    fields[2] = std.builtin.Type.StructField{
        .name = "entities",
        .type = ArrayList(Entity),
        .alignment = @alignOf(ArrayList(Entity)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field: CompDataList: AL(comp)
    inline for(pool_components, 3..) |component, i| {
        const name = @tagName(component);
        const T = CR.getTypeByName(component);
        const archetype_storage = ?*ArrayList(T);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = archetype_storage,
            .alignment = @alignOf(archetype_storage),
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

pub fn ArchetypePoolType(comptime config: PoolConfig) type {
    const req = if(config.req) |req_comps| req_comps else &.{};
    const components_list = if(config.components) |comp| comp else &.{};


    const pool_components = comptime blk: {
        if (req.len == 0 and components_list.len == 0) {
            break :blk &[_]CR.ComponentName{};
        } else if (req.len == 0 and components_list.len > 0) {
            break :blk components_list;
        } else if (req.len > 0 and components_list.len == 0) {
            break :blk req;
        } else {
            break :blk req ++ components_list;
        }
    };

    const name = config.name;

    const POOL_MASK = comptime MaskManager.Comptime.createMask(pool_components);

    const archetype_storage = ComponentArrayStorageType(pool_components);
    const MigrationQueue = MQ.MigrationQueueType(pool_components);
    const EntityOperationQueue = EOQ.EntityOperationQueueType(EntityBuilderType(req, components_list));

    return struct {
        const Self = @This();

        pub const pool_mask = POOL_MASK;

        pub const REQ_MASK = MaskManager.Comptime.createMask(req);

        pub const storage_strategy: StorageStrategy = .ARCHETYPE;
        pub const COMPONENTS = pool_components;
        pub const REQ_COMPONENTS = req;
        pub const COMPONENTS_LIST = components_list;
        pub const NAME = name;
        pub const ARCHETYPE_STORAGE = archetype_storage;

        /// EntityBuilder type for creating entities in this pool
        /// Required components are non-optional fields
        /// Optional components are nullable fields with null defaults
        pub const Builder = EntityBuilderType(req, components_list);

        allocator: std.mem.Allocator,
        archetype_list: ArrayList(archetype_storage),
        mask_list: ArrayList(MaskManager.Mask),

        migration_queue: MigrationQueue,
        entity_operation_queue: EntityOperationQueue,
        new_archetypes: ArrayList(usize),
        reallocated_archetypes: ArrayList(usize), 

        pub fn init(allocator: std.mem.Allocator) !Self {
            const self: Self = .{
                .allocator = allocator,
                .archetype_list = ArrayList(archetype_storage){},
                .mask_list = ArrayList(MaskManager.Mask){},
                .migration_queue = MigrationQueue.init(allocator),
                .entity_operation_queue = EntityOperationQueue.init(allocator),
                .new_archetypes = ArrayList(usize){},
                .reallocated_archetypes = ArrayList(usize){},
            };

            return self;
        }

        pub fn getInterface(self: *Self, entity_manager: *EM.EntityManager) PoolInterfaceType(NAME) {
            return PoolInterfaceType(NAME).init(self, entity_manager);
        }

        fn initArchetype(allocator: std.mem.Allocator, archetype_index: usize, mask: MaskManager.Mask) !archetype_storage {
            var archetype: archetype_storage = undefined;
            archetype.index = archetype_index;
            archetype.reallocating = false;
            archetype.entities = ArrayList(Entity){};

            inline for(pool_components) |component_name| {
                const field_bit = comptime MaskManager.Comptime.componentToBit(component_name);
                const field_name = @tagName(component_name);

                if(MaskManager.maskContains(mask, field_bit)) {
                    const T = CR.getTypeByName(component_name);
                    const array_list_ptr = try allocator.create(ArrayList(T));
                    array_list_ptr.* = ArrayList(T){};
                    @field(archetype, field_name) = array_list_ptr;
                }
                else {
                    @field(archetype, field_name) = null;
                }
            }
            return archetype;
        }

        fn setArchetypeComponent(self: *Self, archetype: *archetype_storage, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void{
            var component_array_ptr = @field(archetype.*, @tagName(component)).?;
            if(component_array_ptr.items.len + 1 > component_array_ptr.capacity and !archetype.reallocating){
                archetype.reallocating = true;
                try self.reallocated_archetypes.append(self.allocator, archetype.index);
            }
            try component_array_ptr.append(self.allocator, data);
        }

        fn getArchetype(self: *Self, mask: MaskManager.Mask) ?usize {
            for(self.mask_list.items, 0..) |existing_mask, i| {
                if(existing_mask == mask) {
                    return i;
                }
            }
            return null;
        }

        fn getOrCreateArchetype(self: *Self, mask: MaskManager.Mask) !usize {
            if(self.getArchetype(mask)) |index| {
                return index;
            }
            else {
                const indx = self.archetype_list.items.len;
                const archetype = try initArchetype(self.allocator, indx, mask);
                try self.archetype_list.append(self.allocator, archetype);
                try self.mask_list.append(self.allocator, mask);

                try self.new_archetypes.append(self.allocator, indx);
                return indx;
            }
        }

        fn getEntityMask(self: *Self, mask_list_index: u32) MaskManager.Mask{
            return self.mask_list[@as(usize, mask_list_index)];
        }

        pub fn addEntity(self: *Self, entity: Entity, component_data: Builder) !struct { storage_index: u32, archetype_index: u32 }{
            // Build component mask at runtime by checking which optional fields are non-null
            // Required components are always included (enforced by Builder type system)
            var mask: MaskManager.Mask = 0;

            inline for (pool_components) |comp| {
                const field_name = @tagName(comp);
                const is_optional = comptime blk: {
                    const field_info = for (std.meta.fields(Builder)) |f| {
                        if (std.mem.eql(u8, f.name, field_name)) break f;
                    } else unreachable;
                    break :blk @typeInfo(field_info.type) == .optional;
                };

                if (!is_optional) {
                    // Required component - always include
                    mask |= comptime MaskManager.Comptime.componentToBit(comp);
                } else {
                    // Optional component - check at runtime if non-null
                    if (@field(component_data, field_name) != null) {
                        mask |= comptime MaskManager.Comptime.componentToBit(comp);
                    }
                }
            }

            const archetype_idx = try self.getOrCreateArchetype(mask);
            const archetype = &self.archetype_list.items[archetype_idx];

            try archetype.entities.append(self.allocator, entity);

            // Store component data for each component in the mask
            inline for (pool_components) |component| {
                const field_bit = comptime MaskManager.Comptime.componentToBit(component);

                if (MaskManager.maskContains(mask, field_bit)) {
                    const T = CR.getTypeByName(component);
                    const field_name = @tagName(component);
                    const field_value = @field(component_data, field_name);

                    // Check if field is optional at comptime, unwrap at runtime if needed
                    const is_optional = comptime blk: {
                        const field_info = for (std.meta.fields(Builder)) |f| {
                            if (std.mem.eql(u8, f.name, field_name)) break f;
                        } else unreachable;
                        break :blk @typeInfo(field_info.type) == .optional;
                    };

                    const unwrapped = if (is_optional) field_value.? else field_value;

                    const typed_data = if (@TypeOf(unwrapped) == T)
                        unwrapped
                    else blk: {
                        var result: T = undefined;
                        inline for (std.meta.fields(T)) |field| {
                            if (!@hasField(@TypeOf(unwrapped), field.name)) {
                                @compileError("Field " ++ field.name ++ " is missing from component " ++
                                    @tagName(component) ++ "!\nMake sure fields of all components are included and spelled properly when using Pool.createEntity()\n");
                            }
                            @field(result, field.name) = @field(unwrapped, field.name);
                        }
                        break :blk result;
                    };

                    try self.setArchetypeComponent(archetype, component, typed_data);
                }
            }
            return .{
                .storage_index = @intCast(archetype.entities.items.len - 1),
                .archetype_index = @intCast(archetype_idx),
            };
        }

        pub fn removeEntity(self: *Self, mask_list_index: u32,  archetype_index: u32, pool_name: PoolName) !Entity {
            try validateEntityInPool(pool_name);
            const mask_list_idx: usize = @intCast(mask_list_index);
            const entity_mask = self.mask_list.items[mask_list_idx];
            var archetype = &self.archetype_list.items[mask_list_idx];

            const swapped_entity = archetype.entities.items[archetype.entities.items.len - 1];
            _ = archetype.entities.swapRemove(archetype_index);

            inline for(pool_components) |component_name| {
                const field_bit = comptime MaskManager.Comptime.componentToBit(component_name);
                const field_name = @tagName(component_name);

                // Only process if this component exists in the entity's mask
                if (MaskManager.maskContains(entity_mask, field_bit)) {
                    const component_array = &@field(archetype, field_name);
                    if(component_array.* != null)  {
                        var comp_array = component_array.*.?;
                        _ = comp_array.swapRemove(archetype_index);
                    }
                }
            }

            // Mark archetype for re-caching since swapRemove changed entity order
            if (!archetype.reallocating) {
                archetype.reallocating = true;
                try self.reallocated_archetypes.append(self.allocator, mask_list_idx);
            }

            return swapped_entity;
        }

        // ============= Deferred Entity Operations =============

        /// Queue entity for creation - will be processed during flushEntityOperations
        pub fn queueEntityCreate(self: *Self, entity: Entity, component_data: Builder) !void {
            try self.entity_operation_queue.queueCreate(entity, component_data);
        }

        /// Queue entity for destruction - will be processed during flushEntityOperations
        pub fn queueEntityDestroy(self: *Self, entity: Entity, storage_index: u32, mask_list_index: u32) !void {
            try self.entity_operation_queue.queueDestroy(entity, storage_index, mask_list_index);
        }

        /// Process all queued entity operations.
        /// Destroys are processed first (in reverse order to avoid index invalidation),
        /// then creates are processed.
        /// Returns slice of results for EntityManager to update slots.
        pub fn flushEntityOperations(self: *Self) ![]EntityOperationResult {
            if (!self.entity_operation_queue.hasQueuedOperations()) {
                return &.{};
            }

            var results = ArrayList(EntityOperationResult){};

            // Sort destroy queue by storage_index descending to avoid index invalidation
            std.mem.sort(
                EntityOperationQueue.DestroyEntry,
                self.entity_operation_queue.destroy_queue.items,
                {},
                struct {
                    fn lessThan(_: void, a: EntityOperationQueue.DestroyEntry, b: EntityOperationQueue.DestroyEntry) bool {
                        return a.storage_index > b.storage_index; // Descending
                    }
                }.lessThan
            );

            // Process destroys first
            for (self.entity_operation_queue.destroy_queue.items) |entry| {
                const swapped_entity = try self.removeEntity(
                    entry.mask_list_index,
                    entry.storage_index,
                    NAME
                );
                try results.append(self.allocator, .{
                    .operation = .destroy,
                    .entity = entry.entity,
                    .storage_index = undefined,
                    .mask_list_index = undefined,
                    .swapped_entity = if (std.meta.eql(entry.entity, swapped_entity)) null else swapped_entity,
                });
            }

            // Then process creates
            for (self.entity_operation_queue.create_queue.items) |entry| {
                const result = try self.addEntity(entry.entity, entry.component_data);
                try results.append(self.allocator, .{
                    .operation = .create,
                    .entity = entry.entity,
                    .storage_index = result.storage_index,
                    .mask_list_index = result.archetype_index,
                    .swapped_entity = null,
                });
            }

            self.entity_operation_queue.clear();
            return try results.toOwnedSlice(self.allocator);
        }

        // ============= End Deferred Entity Operations =============

        pub fn getComponent(
            self: *Self,
            mask_list_index: u32,
            storage_index: u32,
            pool_name: PoolName,
            comptime component: CR.ComponentName) !*CR.getTypeByName(component) {

            validateComponentInPool(component);
            try validateEntityInPool(pool_name);

            const mask_list_idx: usize = @intCast(mask_list_index);
            const entity_mask = self.mask_list.items[mask_list_idx];
            const archetype = &self.archetype_list.items[mask_list_idx];

            try validateComponentInArchetype(entity_mask, component);

            const component_array = @field(archetype, @tagName(component));
            return &component_array.?.items[storage_index];
        }

        pub fn hasComponent(
            self: *Self,
            mask_list_index: u32,
            pool_name: PoolName,
            comptime component: CR.ComponentName) !bool {
            
            validateComponentInPool(component);
            try validateEntityInPool(pool_name);

            const mask_list_idx: usize = @intCast(mask_list_index);
            const entity_mask = self.mask_list.items[mask_list_idx];
            
            const component_bit = MaskManager.Comptime.componentToBit(component);
            return MaskManager.maskContains(entity_mask, component_bit);
        }

        pub fn addOrRemoveComponent(
            self: *Self,
            entity: Entity,
            mask_list_index: u32,
            pool_name: PoolName,
            storage_index: u32,
            is_migrating: bool,
            comptime direction: MoveDirection,
            comptime component: CR.ComponentName,
            data: ?CR.getTypeByName(component)
        ) !void {
            // Compile-time validation: ensure component exists in this pool
            validateComponentInPool(component);

            // Runtime validation: ensure entity belongs to this pool
            try validateEntityInPool(pool_name);

            //Check to make sure user is not remvoving a required component
            comptime {
                if(direction == .removing){
                    for(req) |req_comp| {
                        if(req_comp == component) {
                            @compileError("You can not remove required component "
                                ++ @tagName(component) ++ " from pool " ++ @typeName(Self));
                        }
                    }
                }
            }

            //Make sure component has non-null data when adding component
            //Should be null when removing component
            if(direction == .adding and data == null) {
                std.debug.print("\ncomponent data cannont be null when adding a component!\n", .{});
                return error.NullComponentData;
            }

            const entity_mask = self.mask_list.items[mask_list_index];
            const component_bit = MaskManager.Comptime.componentToBit(component);

            if(direction == .adding) {
                const new_mask = MaskManager.Runtime.addComponent(entity_mask, component);
                if(MaskManager.maskContains(entity_mask, component_bit)) { return error.AddingExistingComponent; }

                const component_data = @unionInit(
                    MigrationQueue.Entry.ComponentDataUnion,
                    @tagName(component),
                    data
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
            }

            else if(direction == .removing){
                const new_mask = MaskManager.Runtime.removeComponent(entity_mask, component);
                if(!MaskManager.maskContains(entity_mask, component_bit)) { return error.RemovingNonexistingComponent; }

                const component_data = @unionInit(
                    MigrationQueue.Entry.ComponentDataUnion,
                    @tagName(component),
                    data
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

        pub fn flushMigrationQueue(self: *Self) ![]MigrationResult{
            if(self.migration_queue.count() == 0) return &.{};
            var results = ArrayList(MigrationResult){};
            try results.ensureTotalCapacity(self.allocator, self.migration_queue.count());

            // Collect all migrations and sort by (old_mask, archetype_index DESC)
            // This prevents swapRemove from invalidating indices of unprocessed entities
            const MigrationWork = struct {
                entity: Entity,
                entries: ArrayList(MigrationQueue.Entry),
                old_mask: MaskManager.Mask,
                archetype_index: u32,
            };

            var work_items = ArrayList(MigrationWork){};
            try work_items.ensureTotalCapacity(self.allocator, self.migration_queue.count());
            defer work_items.deinit(self.allocator);

            var iter = self.migration_queue.iterator();
            while (iter.next()) |kv| {
                const entity = kv.key_ptr.*;
                const entries = kv.value_ptr.*;

                if (entries.items.len == 0) continue;

                const first_entry = entries.items[0];
                try work_items.append(self.allocator, .{
                    .entity = entity,
                    .entries = entries,
                    .old_mask = first_entry.old_mask,
                    .archetype_index = first_entry.storage_index,
                });
            }

            // Sort: primary by old_mask, secondary by archetype_index descending
            std.mem.sort(MigrationWork, work_items.items, {}, struct {
                fn lessThan(_: void, a: MigrationWork, b: MigrationWork) bool {
                    if (a.old_mask != b.old_mask) {
                        return a.old_mask < b.old_mask;
                    }
                    // Reverse order for archetype_index (higher indices first)
                    return a.archetype_index > b.archetype_index;
                }
            }.lessThan);

            // Process migrations in sorted order
            for (work_items.items) |*work| {
                const entity = work.entity;
                var entries = work.entries;
                const original_old_mask = work.old_mask;
                const original_archetype_index = work.archetype_index;

                // Step 1: Resolve - compute final mask from all entries

                var final_mask = original_old_mask;
                for (entries.items) |entry| {
                    if (entry.direction == .adding) {
                        final_mask |= entry.component_mask;
                    } else {
                        final_mask &= ~entry.component_mask;
                    }
                }

                // Step 2: Move - transfer entity + existing components, allocate undefined for new
                const src_index = self.getArchetype(original_old_mask) orelse return error.ArchetypeDoesNotExist;
                const dest_index = try self.getOrCreateArchetype(final_mask);

                const src_archetype = &self.archetype_list.items[src_index];
                const dest_archetype = &self.archetype_list.items[dest_index];

                const move_result = try moveEntity(
                    self.allocator,
                    dest_archetype,
                    final_mask,
                    src_archetype,
                    original_old_mask,
                    original_archetype_index,
                );

                // Mark both source and destination archetypes for re-caching
                // Source: swapRemove changed entity order, invalidating cached pointer indices
                // Destination: entity added, cached pointer arrays have wrong length
                if (!src_archetype.reallocating) {
                    src_archetype.reallocating = true;
                    try self.reallocated_archetypes.append(self.allocator, src_index);
                }
                if (!dest_archetype.reallocating) {
                    dest_archetype.reallocating = true;
                    try self.reallocated_archetypes.append(self.allocator, dest_index);
                }

                // Step 3: Set - write component data for adds
                if (comptime pool_components.len > 0) {
                    for (entries.items) |entry| {
                        if (entry.direction == .adding) {
                            switch (entry.component_data) {
                                inline else => |data, tag| {
                                    // Overwrite the undefined slot with actual data
                                    const dest_array = @field(dest_archetype, @tagName(tag)).?;
                                    dest_array.items[move_result.archetype_index] = data.?;
                                },
                            }
                        }
                    }
                }

                try results.append(self.allocator, MigrationResult{
                    .entity = entity,
                    .storage_index = move_result.archetype_index,
                    .swapped_entity = move_result.swapped_entity,
                    .mask_list_index = @intCast(dest_index),
                });

                // Clean up the entry list
                entries.deinit(self.allocator);
            }

            self.migration_queue.clear();
            return try results.toOwnedSlice(self.allocator);
        }

        fn moveEntity(
            allocator: std.mem.Allocator,
            dest_archetype: *archetype_storage,
            new_mask: MaskManager.Mask,
            src_archetype: *archetype_storage,
            old_mask: MaskManager.Mask,
            archetype_index: u32,
            ) !struct { archetype_index: u32, swapped_entity: ?Entity }{
            const entity = src_archetype.entities.items[archetype_index];
            try dest_archetype.entities.append(allocator, entity);

            const last_index = src_archetype.entities.items.len - 1;
            const swapped = archetype_index != last_index;
            const swapped_entity = if(swapped) src_archetype.entities.items[last_index] else null;
            const new_archetype_index: u32 = @intCast(dest_archetype.entities.items.len - 1);

            // Remove entity from source archetype
            _ = src_archetype.entities.swapRemove(archetype_index);

            inline for(pool_components) |component_name| {
                const field_bit = comptime MaskManager.Comptime.componentToBit(component_name);
                const field_name = @tagName(component_name);

                const in_old = MaskManager.maskContains(old_mask, field_bit);
                const in_new = MaskManager.maskContains(new_mask, field_bit);

                // Component exists in both - copy it over
                if (in_old and in_new) {
                    var dest_array_ptr = @field(dest_archetype, field_name).?;
                    var src_array_ptr = @field(src_archetype, field_name).?;
                    try dest_array_ptr.append(allocator, src_array_ptr.items[archetype_index]);
                    _ = src_array_ptr.swapRemove(archetype_index);
                } 
                // New component being added - allocate undefined, will be set in step 3
                else if (in_new and !in_old) {
                    var dest_array_ptr = @field(dest_archetype, field_name).?;
                    try dest_array_ptr.append(allocator, undefined);
                } 
                // Component being removed - just remove from source
                else if (in_old and !in_new) {
                    var src_array_ptr = @field(src_archetype, field_name).?;
                    _ = src_array_ptr.swapRemove(archetype_index);
                }
                // !in_old and !in_new - component not relevant, skip
            }
            return .{
                .archetype_index = new_archetype_index,
                .swapped_entity = swapped_entity,
            };
        }

        pub fn flushNewAndReallocatingLists(self: *Self) void {
            for(self.reallocated_archetypes.items) |arch_indx|{
                 self.archetype_list.items[arch_indx].reallocating = false;
            }
            self.new_archetypes.clearRetainingCapacity();
            self.reallocated_archetypes.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            // Clean up all archetypes
            for (self.archetype_list.items) |*archetype| {
                archetype.entities.deinit(self.allocator);

                inline for (pool_components) |component_name| {
                    const field_name = @tagName(component_name);
                    //~Field:ComponentName:  ?*ArrayList(T)
                    if (@field(archetype.*, field_name)) |array_ptr| {
                        array_ptr.deinit(self.allocator);
                        self.allocator.destroy(array_ptr);
                    }
                }
            }

            self.archetype_list.deinit(self.allocator);
            self.mask_list.deinit(self.allocator);
            self.new_archetypes.deinit(self.allocator);
            self.reallocated_archetypes.deinit(self.allocator);

            // Clean up queues
            self.migration_queue.deinit();
            self.entity_operation_queue.deinit();
        }

        fn checkIfEntInPool(pool_name: PoolName) bool {
            return pool_name == name;
        }

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

        fn validateComponentInArchetype(archetype_mask: MaskManager.Mask, component: CR.ComponentName) !void {
            if(!MaskManager.maskContains(archetype_mask, MaskManager.Runtime.componentToBit(component))) {
                std.debug.print("\nEntity does not have component: {s}\n", .{@tagName(component)});
                return error.ComponentNotInArchetype;
            }
        }

        fn validateEntityInPool(pool_name: PoolName) !void {
            if(!checkIfEntInPool(pool_name)){
                std.debug.print("\nEntity assigned pool '{s}' does not match pool: {s}\n", .{@tagName(pool_name), @tagName(name)});
                return error.EntityPoolMismatch;
            }
        }

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
