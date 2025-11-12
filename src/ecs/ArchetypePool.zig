// TODO: Prevent cascading migration bug
// When multiple component add/removes happen to the same entity within a frame,
// the migration queue can contain stale archetype_index and mask data.
//
// Solutions to consider:
// 1. Add `is_migrating` flag to EntitySlot (EntityManager.zig)
//    - Check flag in addOrRemoveComponent before queuing
//    - If true, find existing migration entry and merge (update new_mask)
//    - Clear flag after flush completes
//    - Cost: O(1) duplicate check vs current O(n) queue scan
//    - Memory: Check if EntitySlot is already 32-byte aligned (likely zero cost)
//
// 2. Alternative: Use high bit of storage_index as is_migrating flag
//    - Zero memory cost, supports up to 2^31 entities per archetype
//    - Slightly less readable but good for tight packing
//
// 3. Alternative: HashMap<entity_index, queue_index> in ArchetypePool
//    - O(1) lookup but extra allocation per pool
//    - More memory overhead than flag approach

const std = @import("std");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PR = @import("PoolRegistry.zig");
const PoolInterface = @import("PoolInterface.zig").PoolInterface;
const EntityBuilderFn = @import("EntityBuilder.zig").EntityBuilder;

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
        const archetype_type = ?*ArrayList(T);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = archetype_type,
            .alignment = @alignOf(archetype_type),
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

const MoveDirection = enum {
    adding,
    removing,
};

fn MigrationEntry(comptime pool_components: []const CR.ComponentName) type {
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
        old_mask: CR.ComponentMask,
        new_mask: CR.ComponentMask,
        component_data: ComponentDataUnion,
    };
}

const MigrationResult = struct {
    entity: Entity,
    archetype_index: u32,
    entity_mask: CR.ComponentMask,
    swapped_entity: ?Entity,
};

pub fn ArchetypePool(comptime req: []const CR.ComponentName, comptime opt: []const CR.ComponentName) type {
    const pool_components = req ++ opt;
    const archetype_type = ComponentArrayStorage(pool_components);
    const POOL_MASK = comptime MM.Comptime.createMask(pool_components);
    
    return struct {
        const Self = @This();
        const pool_name = std.meta.stringToEnum(PR.pool_name, @typeName(@TypeOf(Self))) orelse @compileError("Pool not registred");

        pub const pool_mask = POOL_MASK;
        pub const REQ_MASK = MM.Comptime.createMask(req);
        pub const COMPONENTS = pool_components;
        pub const REQ_COMPONENTS = req;
        pub const OPT_COMPONENTS = opt;

        /// EntityBuilder type for creating entities in this pool
        /// Required components are non-optional fields
        /// Optional components are nullable fields with null defaults
        pub const Builder = EntityBuilderFn(req, opt);

        pool_is_dirty: bool = false,
        allocator: std.mem.Allocator,
        archetype_list: ArrayList(archetype_type),
        mask_list: ArrayList(CR.ComponentMask),

        migration_queue: ArrayList(MigrationEntry(pool_components)),
        new_archetypes: ArrayList(usize),
        new_empty_archetypes: ArrayList(usize),

        pub fn init(allocator: std.mem.Allocator) !Self {
            const self: Self = .{
                .allocator = allocator,
                .archetype_list = ArrayList(archetype_type){},
                .mask_list = ArrayList(CR.ComponentMask){},
                .migration_queue = ArrayList(MigrationEntry(pool_components)){},
                .new_archetypes = ArrayList(usize){},
                .new_empty_archetypes = ArrayList(usize){},
            };

            return self;
        }

        pub fn getInterface(self: *Self, entity_manager: *EM.EntityManager) PoolInterface(.{.req = req, .opt = opt}) {
            return PoolInterface(.{.req = req, .opt = opt}).init(self, entity_manager);
        }

        fn initArchetype(allocator: std.mem.Allocator, mask: CR.ComponentMask) !archetype_type {
            var archetype: archetype_type = undefined;
            inline for(@typeInfo(archetype_type).@"struct".fields) |field| {
                if(comptime std.mem.eql(u8, "entities", field.name)) {
                    @field(archetype, field.name) = ArrayList(Entity){};
                } else {
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MM.Comptime.componentToBit(component_name);

                    if(MM.maskContains(mask, field_bit)) {
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

        fn setArchetypeComponent(allocator: std.mem.Allocator, archetype: *archetype_type, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void{
            var component_array_ptr = @field(archetype.*, @tagName(component)).?;
            try component_array_ptr.append(allocator, data);
        }

        fn getArchetype(self: *Self, mask: CR.ComponentMask) ?usize {
            for(self.mask_list.items, 0..) |existing_mask, i| {
                if(existing_mask == mask) {
                    return i;
                }
            }
            return null;
        }

        fn getOrCreateArchetype(self: *Self, mask: CR.ComponentMask) !usize {
            if(self.getArchetype(mask)) |index| {
                return index;
            }
            else {
                const archetype = try initArchetype(self.allocator, mask);
                try self.archetype_list.append(self.allocator, archetype);
                try self.mask_list.append(self.allocator, mask);
                return self.archetype_list.items.len - 1;
            }
        }

        pub fn addEntity(self: *Self, entity: Entity, comptime component_data: Builder) !struct { index: u32, mask: CR.ComponentMask }{
            // Build list of non-null components and validate required components
            const components = comptime blk: {
                var component_list: [pool_components.len]CR.ComponentName = undefined;
                var count: usize = 0;

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

            const mask = comptime MM.Comptime.createMask(&components);
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
                .index = @intCast(archetype.entities.items.len - 1),
                .mask = mask,
            };
        }

        pub fn remove_entity(self: *Self, archetype_index: u32, entity_mask: CR.ComponentMask, entity_pool_mask: CR.ComponentMask) !Entity {
            try validateEntityInPool(entity_pool_mask);
            const archetype_idx = self.getArchetype(entity_mask) orelse return error.ArchetypeDoesNotExist;
            var archetype = &self.archetype_list.items[archetype_idx];

            const swapped_entity = archetype.entities.items[archetype.entities.items.len - 1];
            _ = archetype.entities.swapRemove(archetype_index);

            inline for(@typeInfo(archetype_type).@"struct".fields) |field| {
                if(!comptime std.mem.eql(u8, "entities", field.name)) {
                    // Get component bit at comptime
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MM.Comptime.componentToBit(component_name);

                    // Only process if this component exists in the entity's mask
                    if (MM.maskContains(entity_mask, field_bit)) {
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
            archetype_index: u32,
            entity_mask: CR.ComponentMask,
            entity_pool_mask: CR.ComponentMask,
            comptime component: CR.ComponentName) !*CR.getTypeByName(component) {

            validateComponentInPool(component);
            try validateEntityInPool(entity_pool_mask);
            try validateComponentInArchetype(entity_mask, component);

            const archetype_idx = self.getArchetype(entity_mask) orelse return error.ArchetypeDoesNotExist;
            const archetype = &self.archetype_list.items[archetype_idx];

            const component_array = @field(archetype, @tagName(component));
            return &component_array.?.items[archetype_index];
        }

        pub fn addOrRemoveComponent(
            self: *Self,
            entity: Entity,
            entity_mask: CR.ComponentMask,
            entity_pool_mask: CR.ComponentMask,
            archetype_index: u32,
            comptime direction: MoveDirection,
            comptime component: CR.ComponentName,
            data: ?CR.getTypeByName(component)
        ) !void {
            // Compile-time validation: ensure component exists in this pool
            validateComponentInPool(component);

            // Runtime validation: ensure entity belongs to this pool
            try validateEntityInPool(entity_pool_mask);

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

            const component_bit = MM.Comptime.componentToBit(component);

            if(direction == .adding) {
                const new_mask = MM.Runtime.addComponent(entity_mask, component);
                if(MM.maskContains(entity_mask, component_bit)) { return error.AddingExistingComponent; }

                const migration = MigrationEntry(pool_components) {
                    .entity = entity,
                    .archetype_index = archetype_index, 
                    .old_mask = entity_mask,
                    .new_mask = new_mask,
                    .direction = .adding,
                    .component_data = @unionInit(
                        MigrationEntry(pool_components).ComponentDataUnion,
                        @tagName(component),
                        data
                    ),
                };

                try self.migration_queue.append(self.allocator, migration);
            }

            else if(direction == .removing){
                const new_mask = MM.Runtime.removeComponent(entity_mask, component);
                if(!MM.maskContains(entity_mask, component_bit)) { return error.RemovingNonexistingComponent; }

                const migration = MigrationEntry(pool_components) {
                    .entity = entity,
                    .archetype_index = archetype_index, 
                    .old_mask = entity_mask,
                    .new_mask = new_mask,
                    .direction = .removing,
                    .component_data = @unionInit(
                        MigrationEntry(pool_components).ComponentDataUnion,
                        @tagName(component),
                        data
                    ),
                };

                try self.migration_queue.append(self.allocator, migration);
            }
        }

        pub fn flushMigrationQueue(self: *Self) ![]MigrationResult{
            if(self.migration_queue.items.len == 0 ) return &.{};
            var results = ArrayList(MigrationResult){};
            try results.ensureTotalCapacity(self.allocator, self.migration_queue.items.len);

            std.mem.sort(
                MigrationEntry(pool_components),
                self.migration_queue.items,
                {},
                struct {
                    fn lessThan(_: void, a: MigrationEntry(pool_components), b: MigrationEntry(pool_components)) bool{
                        return a.old_mask < b.old_mask;
                    }
                }.lessThan,
            );

            for(self.migration_queue.items) |entry| {
                const migration_result = switch(entry.component_data){
                    inline else => |data, tag| blk: {
                        // Convert MigrationTag to ComponentName via tag name
                        const component = comptime std.meta.stringToEnum(CR.ComponentName, @tagName(tag)).?;

                        // Get source archetype INDEX first (not pointer)
                        const src_index = self.getArchetype(entry.old_mask) orelse return error.ArchetypeDoesNotExist;

                        // Create dest archetype (may reallocate archetype_list)
                        const dest_index = try self.getOrCreateArchetype(entry.new_mask);

                        // NOW get pointers after potential reallocation
                        const src_archetype = &self.archetype_list.items[src_index];
                        const dest_archetype = &self.archetype_list.items[dest_index];

                        const result = try moveEntity(
                            self.allocator,
                            dest_archetype,
                            entry.new_mask,
                            src_archetype,
                            entry.old_mask,
                            entry.archetype_index,
                            entry.direction
                        );

                        if(entry.direction == .adding) {
                            try setArchetypeComponent(self.allocator, dest_archetype, component, data.?);
                        }

                        break :blk MigrationResult{
                            .entity= entry.entity,
                            .archetype_index = result.archetype_index,
                            .swapped_entity = result.swapped_entity,
                            .entity_mask = entry.new_mask,
                        };
                    }
                };
                try results.append(self.allocator, migration_result);
            }

            self.migration_queue.clearRetainingCapacity();
            return try results.toOwnedSlice(self.allocator);
        }

        fn moveEntity(
            allocator: std.mem.Allocator,
            dest_archetype: *archetype_type,
            new_mask: CR.ComponentMask,
            src_archetype: *archetype_type,
            old_mask: CR.ComponentMask,
            archetype_index: u32,
            direction: MoveDirection
            ) !struct { archetype_index: u32, swapped_entity: ?Entity }{
            const entity= src_archetype.entities.items[archetype_index];
            try dest_archetype.entities.append(allocator, entity);

            const last_index = src_archetype.entities.items.len - 1;
            const swapped = archetype_index != last_index;
            const swapped_entity = if(swapped) src_archetype.entities.items[last_index] else null;
            const new_archetype_index: u32 = @intCast(dest_archetype.entities.items.len - 1);

            // Remove entity from source archetype
            _ = src_archetype.entities.swapRemove(archetype_index);

            inline for(@typeInfo(archetype_type).@"struct".fields) |field| {
                if(!comptime std.mem.eql(u8, "entities", field.name)) {
                    // Get component bit at comptime
                    const component_name = comptime std.meta.stringToEnum(CR.ComponentName, field.name).?;
                    const field_bit = comptime MM.Comptime.componentToBit(component_name);

                    // Skip if component doesn't exist in either mask
                    if (MM.maskContains(new_mask, field_bit) or MM.maskContains(old_mask, field_bit)) {
                        const maybe_src = &@field(src_archetype, field.name);
                        const maybe_dest = &@field(dest_archetype, field.name);

                        // Component exists in src but not in dest
                        if(maybe_src.* != null and maybe_dest.* == null) {
                            if(direction == .adding) return error.ComponentLostDuringAdd; // This shouldn't happen when adding
                            // For .removing, this is expected - just skip copying this component
                        } else if(maybe_dest.* != null and maybe_src.* != null) {
                            // Component exists in both - copy it over
                            var dest_array_ptr = maybe_dest.*.?;
                            var src_array_ptr = maybe_src.*.?;
                            try dest_array_ptr.append(allocator, src_array_ptr.items[archetype_index]);
                            _ = src_array_ptr.swapRemove(archetype_index);
                        }
                    }
                }
                // Component exists in new but not old (.adding case) - will be set separately
            }
            return .{
                .archetype_index = new_archetype_index,
                .swapped_entity = swapped_entity,
            };
        }

        pub fn deinit(self: *Self) void {
            // Clean up all archetypes
            for (self.archetype_list.items) |*archetype| {
                inline for (@typeInfo(archetype_type).@"struct".fields) |field| {
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
            self.migration_queue.deinit(self.allocator);
        }

        fn checkIfEntInPool(entity_pool_mask: CR.ComponentMask) bool {
            return entity_pool_mask == pool_mask;
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

        fn validateComponentInArchetype(archetype_mask: CR.ComponentMask, component: CR.ComponentName) !void {
            if(!MM.maskContains(archetype_mask, MM.Runtime.componentToBit(component))) {
                std.debug.print("\nEntity does not have component: {s}\n", .{@tagName(component)});
                return error.ComponentNotInArchetype;
            }
        }

        fn validateEntityInPool(entity_pool_mask: CR.ComponentMask) !void {
            if(!checkIfEntInPool(entity_pool_mask)){
                std.debug.print("\nEntity assigned pool does not match pool: {s}\n", .{@typeName(Self)});
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

    const Pool = ArchetypePool(&.{}, &.{.Position, .Velocity});
    var pool = try Pool.init(allocator);
    defer pool.deinit();
    const dummy_ent = Entity{.index = 0, .generation = 0};
    const ent1 = try pool.addEntity(dummy_ent, .{.Position = .{.x = 3, .y = 2}});

    try pool.addOrRemoveComponent(dummy_ent, ent1.mask, Pool.pool_mask, ent1.index, .adding, .Velocity, .{.dx = 1, .dy = 1});
    const results = try pool.flushMigrationQueue();
    defer allocator.free(results);
}
