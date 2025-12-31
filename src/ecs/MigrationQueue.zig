// Migration System:
// Uses HashMap<Entity, ArrayList(MigrationEntry)> to handle cascading migrations.
// When multiple add/removes happen to the same entity within a frame:
// - is_migrating flag on EntitySlot enables O(1) check before hashmap lookup
// - All migrations for an entity are collected in a list
// - On flush: resolve final mask, single move, then set all new component data
// This prevents stale storage_index bugs and ensures one move per entity per flush.

const std = @import("std");
const CR = @import("../registries/ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");

const ArrayList = std.ArrayList;
const Entity = EM.Entity;
const MaskManager = MM.GlobalMaskManager;

pub const MoveDirection = enum {
    adding,
    removing,
};

pub fn MigrationEntryType(comptime pool_components: []const CR.ComponentName, comptime Mask: type) type {
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

    const CompDataUnion = @Type(.{
        .@"union" = .{
            .fields = &fields,
            .layout = .auto,
            .decls = &.{},
            .tag_type = MigrationTag,
        }
    });

    return struct {
        const Self = @This();
        pub const ComponentDataUnion = CompDataUnion;

        entity: Entity,
        storage_index: u32,
        direction: MoveDirection,
        old_mask: Mask,
        new_mask: Mask,
        component_mask: Mask,
        component_data: ComponentDataUnion,
    };
}

pub const MigrationResult = struct {
    entity: Entity,
    storage_index: u32,
    mask_list_index: u32,
    swapped_entity: ?Entity,
};

pub fn MigrationQueueType(comptime pool_components: []const CR.ComponentName) type {
    const MigrationEntry = MigrationEntryType(pool_components, MaskManager.Mask);

    return struct {
        const Self = @This();
        pub const Entry = MigrationEntry;

        migration_map: std.AutoHashMap(Entity, ArrayList(MigrationEntry)),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .migration_map = std.AutoHashMap(Entity, ArrayList(MigrationEntry)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn addMigration(
            self: *Self,
            entity: Entity,
            storage_index: u32,
            old_mask: MaskManager.Mask,
            new_mask: MaskManager.Mask,
            direction: MoveDirection,
            component_mask: MaskManager.Mask,
            component_data: MigrationEntry.ComponentDataUnion,
            is_migrating: bool,
        ) !void {
            const migration = MigrationEntry{
                .entity = entity,
                .storage_index = storage_index,
                .old_mask = old_mask,
                .new_mask = new_mask,
                .direction = direction,
                .component_mask = component_mask,
                .component_data = component_data,
            };

            if (is_migrating) {
                // Entity already has pending migrations - append to existing list
                const entry_list = self.migration_map.getPtr(entity).?;
                try entry_list.append(self.allocator, migration);
            } else {
                // First migration for this entity - create new list
                var list = ArrayList(MigrationEntry){};
                try list.append(self.allocator, migration);
                try self.migration_map.put(entity, list);
            }
        }

        pub fn count(self: *const Self) usize {
            return self.migration_map.count();
        }

        pub fn clear(self: *Self) void {
            self.migration_map.clearRetainingCapacity();
        }

        pub fn iterator(self: *Self) std.AutoHashMap(Entity, ArrayList(MigrationEntry)).Iterator {
            return self.migration_map.iterator();
        }

        pub fn deinit(self: *Self) void {
            var iter = self.migration_map.valueIterator();
            while (iter.next()) |entry_list| {
                entry_list.deinit(self.allocator);
            }
            self.migration_map.deinit();
        }
    };
}
