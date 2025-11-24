// Migration System:
// Uses HashMap<Entity, ArrayList(MigrationEntry)> to handle cascading migrations.
// When multiple add/removes happen to the same entity within a frame:
// - is_migrating flag on EntitySlot enables O(1) check before hashmap lookup
// - All migrations for an entity are collected in a list
// - On flush: resolve final mask, single move, then set all new component data
// This prevents stale archetype_index bugs and ensures one move per entity per flush.

const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PR = @import("PoolRegistry.zig");
const PoolInterface = @import("PoolInterface.zig").PoolInterface;
const EntityBuilderFn = @import("EntityBuilder.zig").EntityBuilder;
const MaskManager = MM.GlobalMaskManager;

const ArrayList = std.ArrayList;
const Entity = EM.Entity;

fn ComponentArrayStorage(comptime pool_components: []const CR.ComponentName) type {
    var fields: [pool_components.len + 1]std.builtin.Type.StructField = undefined;

    fields[0] = std.builtin.Type.StructField{
        .name = "entities",
        .type = ArrayList(Entity),
        .alignment = @alignOf(ArrayList(Entity)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    inline for(pool_components, 1..) |component, i| {
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
}Error detected while processing BufEnter Autocommands for "<buffer=8>":
Error executing lua callback: /home/dogmaticpolack/.config/nvim/lua/plugins/zls.lua:23: attempt to call field 'on_attach' (a nil value)
stack traceback:
        /home/dogmaticpolack/.config/nvim/lua/plugins/zls.lua:23: in function '_on_attach'
        ...share/nvim/lazy/nvim-lspconfig/lua/lspconfig/configs.lua:260: in function '_setup_buffer'
        ...share/nvim/lazy/nvim-lspconfig/lua/lspconfig/configs.lua:221: in function <...share/nvim/lazy/nvim-lspconfig/lua/lspconfig/configs.lua:220>
Press ENTER or type command to continue

const MoveDirection = enum {
    adding,
    removing,
};

fn MigrationEntry(comptime pool_components: []const CR.ComponentName, comptime Mask: type) type {
    // Create enum fields for the migration tag type
    var enum_fields: [pool_components.len]std.builtin.Type.EnumField = undefined;
    inline for(pool_components, 0..) |component, i| {
        enum_fields[i] = .{
            .name = @tagName(component),
            .value = i,
        };
    }

    const MigrationTag = @Type(.{
        .@"enum" = .{
            .tag_type = u32,
            .fields = &enum_fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });

    // Create union fields
    var fields: [pool_components.len]std.builtin.Type.UnionField = undefined;

    inline for(pool_components, 0..) |component, i| {
        const T = CR.getTypeByName(component);
        fields[i] = std.builtin.Type.UnionField{
            .name = @tagName(component),
            .type = ?T,
            .alignment = @alignOf(T),
        };
    }

    const CompDataUnion=  @Type(.{
        .@"union" = .{
            .fields = &fields,
            .layout = .auto,
            .decls = &.{},
            .tag_type = MigrationTag,
        }
    });

    return struct {
        const Self = @This();
        const ComponentDataUnion = CompDataUnion;

        entity: Entity,
        archetype_index: u32,
        direction: MoveDirection,
        old_mask: Mask,
        new_mask: Mask,
        component_mask: Mask,
        component_data: ComponentDataUnion,
    };
}

const MigrationResult = struct {
    entity: Entity,
    archetype_index: u32,
    mask_list_index: u32,
    swapped_entity: ?Entity,
};

pub fn ArchetypePool(comptime req: []const CR.ComponentName, comptime opt: []const CR.ComponentName, comptime name: PR.PoolName) type {
    const pool_components = req ++ opt;

    const POOL_MASK = comptime MaskManager.Comptime.createMask(pool_components);

    const archetype_storage = ComponentArrayStorage(pool_components);
    const MigrationEntryType = comptime MigrationEntry(pool_components, MaskManager.Mask);

    return struct {
        const Self = @This();

        pub const pool_mask = POOL_MASK;
        pub const REQ_MASK = MaskManager.Comptime.createMask(req);

        pub const COMPONENTS = pool_components;
        pub const REQ_COMPONENTS = req;
        pub const OPT_COMPONENTS = opt;
        pub const NAME = name;
        pub const ARCHETYPE_STORAGE = archetype_storage;

        /// EntityBuilder type for creating entities in this pool
        /// Required components are non-optional fields
        /// Optional components are nullable fields with null defaults
        pub const Builder = EntityBuilderFn(req, opt);

        pool_is_dirty: bool = false,
        allocator: std.mem.Allocator,
        archetype_list: ArrayList(archetype_storage),
        mask_list: ArrayList(MaskManager.Mask),

        migration_map: std.AutoHashMap(Entity, ArrayList(MigrationEntryType)),
        new_archetypes: ArrayList(usize),
        reallocated_archetypes: ArrayList(usize), 

        pub fn init(allocator: std.mem.Allocator) !Self {
            const self: Self = .{
                .allocator = allocator,
                .archetype_list = ArrayList(archetype_storage){},
                .mask_list = ArrayList(MaskManager.Mask){},
                .migration_map = std.AutoHashMap(Entity, ArrayList(MigrationEntryType)).init(allocator),
                .new_archetypes = ArrayList(usize){},
                .reallocated_archetypes = ArrayList(usize){},
            };

            return self;
        }

        pub fn getInterface(self: *Self, entity_manager: *EM.EntityManager) PoolInterface(.{.req = req, .opt = opt, .name = NAME}) {
            return PoolInterface(.{.req = req, .opt = opt, .name = NAME}).init(self, entity_manager);
        }

        fn initArchetype(allocator: std.mem.Allocator, mask: MaskManager.Mask) !archetype_storage {
            var archetype: archetype_storage = undefined;
            inline for(@typeInfo(archetype_storage).@"struct".fields) |field| {
                if(comptime std.mem.eql(u8, "entities", field.name)) {
                    @field(archetype, field.name) = ArrayList(Entity){};
                } else {
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MaskManager.Comptime.componentToBit(component_name);

                    if(MaskManager.maskContains(mask, field_bit)) {
                        const T = CR.getTypeByName(component_name);
                        const array_list_ptr = try allocator.create(ArrayList(T));
                        array_list_ptr.* = ArrayList(T){};
                        @field(archetype, field.name) = array_list_ptr;
                    }
                    else {
                        @field(archetype, field.name) = null;
                    }
                }
            }
            return archetype;
        }

        fn setArchetypeComponent(allocator: std.mem.Allocator, archetype: *archetype_storage, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void{
            var component_array_ptr = @field(archetype.*, @tagName(component)).?;
            try component_array_ptr.append(allocator, data);
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
                const archetype = try initArchetype(self.allocator, mask);
                try self.archetype_list.append(self.allocator, archetype);
                try self.mask_list.append(self.allocator, mask);

                const indx = self.archetype_list.items.len - 1;
                try self.new_archetypes.append(self.allocator, indx);
                return indx;
            }
        }

        fn getEntityMask(self: *Self, mask_list_index: u32) MaskManager.Mask{
            return self.mask_list[@as(usize, mask_list_index)];
        }

        pub fn addEntity(self: *Self, entity: Entity, comptime component_data: Builder) !struct { storage_index: u32, archetype_index: u32 }{
            // Build list of non-null components and validate required components
            const components = comptime blk: {
                var component_list: [pool_components.len]CR.ComponentName = undefined; var count: usize = 0;

                // Check all Builder fields
                // Note: Builder is generated from this pool's req + opt, so all fields are valid
                for (std.meta.fields(Builder)) |field| {
                    const comp = std.meta.stringToEnum(CR.ComponentName, field.name) orelse {
                        @compileError("Component not found in registry");
                    };

                    // Check if this field is optional
                    const is_optional = @typeInfo(field.type) == .optional;
                    const field_value = @field(component_data, field.name);

                    // Include if: required field OR optional field with non-null value
                    const should_include = !is_optional or (field_value != null);

                    if (should_include) {
                        component_list[count] = comp;
                        count += 1;
                    }
                }

                break :blk component_list[0..count].*;
            };

            // Note: Required component validation is handled by Builder type system
            // Builder has non-optional fields for all required components, so they must be provided

            const mask = comptime MaskManager.Comptime.createMask(&components);
            const archetype_idx = try self.getOrCreateArchetype(mask);
            const archetype = &self.archetype_list.items[archetype_idx];

            try archetype.entities.append(self.allocator, entity);

            // Store component data for each non-null component
            inline for(components) |component| {
                const T = CR.getTypeByName(component);
                const field_value = @field(component_data, @tagName(component));

                // Unwrap optional if needed
                const data = comptime blk: {
                    const field_info = for (std.meta.fields(Builder)) |f| {
                        if (std.mem.eql(u8, f.name, @tagName(component))) break f;
                    } else unreachable;

                    const is_optional = @typeInfo(field_info.type) == .optional;
                    if (is_optional) {
                        break :blk field_value.?; // Unwrap the optional
                    } else {
                        break :blk field_value; // Already non-optional
                    }
                };

                const typed_data = if (@TypeOf(data) == T)
                    data
                else blk: {
                    var result: T = undefined;
                    inline for(std.meta.fields(T)) |field| {
                        if(!@hasField(@TypeOf(data), field.name)) {
                            @compileError("Field " ++ field.name ++ " is missing from component "
                                ++ @tagName(component) ++ "!\nMake sure fields of all components are included and spelled properly when using Pool.createEntity()\n");
                        }
                        @field(result, field.name) = @field(data, field.name);
                    }
                    break :blk result;
                };

                try setArchetypeComponent(self.allocator, archetype, component, typed_data);
            }
            return .{
                .storage_index = @intCast(archetype.entities.items.len - 1),
                .archetype_index = @intCast(archetype_idx),
            };
        }

        pub fn remove_entity(self: *Self, mask_list_index: u32,  archetype_index: u32, entity_pool: PR.PoolName) !Entity {
            try validateEntityInPool(entity_pool);
            const mask_list_idx: usize = @intCast(mask_list_index);
            const entity_mask = self.mask_list[mask_list_idx];
            var archetype = &self.archetype_list.items[mask_list_idx];

            const swapped_entity = archetype.entities.items[archetype.entities.items.len - 1];
            _ = archetype.entities.swapRemove(archetype_index);

            inline for(@typeInfo(archetype_storage).@"struct".fields) |field| {
                if(!comptime std.mem.eql(u8, "entities", field.name)) {
                    // Get component bit at comptime
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MaskManager.Comptime.componentToBit(component_name);

                    // Only process if this component exists in the entity's mask
                    if (MaskManager.maskContains(entity_mask, field_bit)) {
                        const component_array = &@field(archetype, field.name);
                        if(component_array.* != null)  {
                            var comp_array = component_array.*.?;
                            _ = comp_array.swapRemove(archetype_index);
                        }
                    }
                }
            }
            return swapped_entity;
        }

        pub fn getComponent(
            self: *Self,
            mask_list_index: u32,
            storage_index: u32,
            entity_pool: PR.PoolName,
            comptime component: CR.ComponentName) !*CR.getTypeByName(component) {

            validateComponentInPool(component);
            try validateEntityInPool(entity_pool);

            const mask_list_idx: usize = @intCast(mask_list_index);
            const entity_mask = self.mask_list[mask_list_idx];
            const archetype = &self.archetype_list.items[mask_list_idx];

            try validateComponentInArchetype(entity_mask, component);

            const component_array = @field(archetype, @tagName(component));
            return &component_array.?.items[storage_index];
        }

        pub fn addOrRemoveComponent(
            self: *Self,
            entity: Entity,
            mask_list_index: u32,
            pool_name: PR.PoolName,
            archetype_index: u32,
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
            if(direction == .adding and data == null) {
                std.debug.print("\ncomponent data cannont be null when adding a component!\n", .{});
                return error.NullComponentData;
            }

            const entity_mask = self.mask_list.items[mask_list_index];
            const component_bit = MaskManager.Comptime.componentToBit(component);

            if(direction == .adding) {
                const new_mask = MaskManager.Runtime.addComponent(entity_mask, component);
                if(MaskManager.maskContains(entity_mask, component_bit)) { return error.AddingExistingComponent; }

                const migration = MigrationEntryType {
                    .entity = entity,
                    .archetype_index = archetype_index,
                    .old_mask = entity_mask,
                    .new_mask = new_mask,
                    .direction = .adding,
                    .component_mask = component_bit,
                    .component_data = @unionInit(
                        MigrationEntryType.ComponentDataUnion,
                        @tagName(component),
                        data
                    ),
                };

                if (is_migrating) {
                    // Entity already has pending migrations - append to existing list
                    const entry_list = self.migration_map.getPtr(entity).?;
                    try entry_list.append(self.allocator, migration);
                } else {
                    // First migration for this entity - create new list
                    var list = ArrayList(MigrationEntryType){};
                    try list.append(self.allocator, migration);
                    try self.migration_map.put(entity, list);
                }
            }

            else if(direction == .removing){
                const new_mask = MaskManager.Runtime.removeComponent(entity_mask, component);
                if(!MaskManager.maskContains(entity_mask, component_bit)) { return error.RemovingNonexistingComponent; }

                const migration = MigrationEntryType {
                    .entity = entity,
                    .archetype_index = archetype_index,
                    .old_mask = entity_mask,
                    .new_mask = new_mask,
                    .direction = .removing,
                    .component_mask = component_bit,
                    .component_data = @unionInit(
                        MigrationEntryType.ComponentDataUnion,
                        @tagName(component),
                        data
                    ),
                };

                if (is_migrating) {
                    // Entity already has pending migrations - append to existing list
                    const entry_list = self.migration_map.getPtr(entity).?;
                    try entry_list.append(self.allocator, migration);
                } else {
                    // First migration for this entity - create new list
                    var list = ArrayList(MigrationEntryType){};
                    try list.append(self.allocator, migration);
                    try self.migration_map.put(entity, list);
                }
            }
        }

        pub fn flushMigrationQueue(self: *Self) ![]MigrationResult{
            if(self.migration_map.count() == 0) return &.{};
            var results = ArrayList(MigrationResult){};
            try results.ensureTotalCapacity(self.allocator, self.migration_map.count());

            var iter = self.migration_map.iterator();
            while (iter.next()) |kv| {
                const entity = kv.key_ptr.*;
                const entries = kv.value_ptr.*;

                if (entries.items.len == 0) continue;

                // Step 1: Resolve - compute final mask from all entries
                const first_entry = entries.items[0];
                const original_old_mask = first_entry.old_mask;
                const original_archetype_index = first_entry.archetype_index;

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

                // Step 3: Set - write component data for adds
                for (entries.items) |entry| {
                    if (entry.direction == .adding) {
                        switch (entry.component_data) {
                            inline else => |data, tag| {
                                // Overwrite the undefined slot with actual data
                                const dest_array = @field(dest_archetype, @tagName(tag)).?;
                                dest_array.items[move_result.archetype_index] = data.?;
                            }
                        }
                    }
                }

                try results.append(self.allocator, MigrationResult{
                    .entity = entity,
                    .archetype_index = move_result.archetype_index,
                    .swapped_entity = move_result.swapped_entity,
                    .mask_list_index = @intCast(dest_index),
                });

                // Clean up the entry list
                kv.value_ptr.deinit(self.allocator);
            }

            self.migration_map.clearRetainingCapacity();
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

            inline for(@typeInfo(archetype_storage).@"struct".fields) |field| {
                if(!comptime std.mem.eql(u8, "entities", field.name)) {
                    // Get component bit at comptime
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MaskManager.Comptime.componentToBit(component_name);

                    const in_old = MaskManager.maskContains(old_mask, field_bit);
                    const in_new = MaskManager.maskContains(new_mask, field_bit);

                    if (in_old and in_new) {
                        // Component exists in both - copy it over
                        var dest_array_ptr = @field(dest_archetype, field.name).?;
                        var src_array_ptr = @field(src_archetype, field.name).?;
                        try dest_array_ptr.append(allocator, src_array_ptr.items[archetype_index]);
                        _ = src_array_ptr.swapRemove(archetype_index);
                    } else if (in_new and !in_old) {
                        // New component being added - allocate undefined, will be set in step 3
                        var dest_array_ptr = @field(dest_archetype, field.name).?;
                        try dest_array_ptr.append(allocator, undefined);
                    } else if (in_old and !in_new) {
                        // Component being removed - just remove from source
                        var src_array_ptr = @field(src_archetype, field.name).?;
                        _ = src_array_ptr.swapRemove(archetype_index);
                    }
                    // !in_old and !in_new - component not relevant, skip
                }
            }
            return .{
                .archetype_index = new_archetype_index,
                .swapped_entity = swapped_entity,
            };
        }

        pub fn deinit(self: *Self) void {
            // Clean up all archetypes
            for (self.archetype_list.items) |*archetype| {
                inline for (@typeInfo(archetype_storage).@"struct".fields) |field| {
                    if(comptime std.mem.eql(u8, field.name, "entities")) {
                        @field(archetype.*, field.name).deinit(self.allocator);
                    } else {
                        // Field is ?*ArrayList(T)
                        if (@field(archetype.*, field.name)) |array_ptr| {
                            array_ptr.deinit(self.allocator);
                            self.allocator.destroy(array_ptr);
                        }
                    }
                }
            }

            self.archetype_list.deinit(self.allocator);
            self.mask_list.deinit(self.allocator);
            self.new_archetypes.deinit(self.allocator);
            self.reallocated_archetypes.deinit(self.allocator);

            // Clean up migration map
            var iter = self.migration_map.valueIterator();
            while (iter.next()) |entry_list| {
                entry_list.deinit(self.allocator);
            }
            self.migration_map.deinit();
        }

        fn checkIfEntInPool(entity_pool_name: PR.PoolName) bool {
            return entity_pool_name == name;
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

        fn validateEntityInPool(entity_pool_name: PR.PoolName) !void {
            if(!checkIfEntInPool(entity_pool_name)){
                std.debug.print("\nEntity assigned pool '{s}' does not match pool: {s}\n", .{@tagName(entity_pool_name), @tagName(name)});
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

test "flush" {
    const allocator = std.testing.allocator;

    const Pool = ArchetypePool(&.{}, &.{.Position, .Velocity}, .MovementPool);
    var pool = try Pool.init(allocator);
    defer pool.deinit();
    const dummy_ent = Entity{.index = 0, .generation = 0};
    const ent1 = try pool.addEntity(dummy_ent, .{.Position = .{.x = 3, .y = 2}});

    try pool.addOrRemoveComponent(dummy_ent, ent1.archetype_index, Pool.NAME, ent1.storage_index, false, .adding, .Velocity, .{.dx = 1, .dy = 1});
    const results = try pool.flushMigrationQueue();
    defer allocator.free(results);
}
