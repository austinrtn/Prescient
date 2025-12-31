const std = @import("std");
const AP = @import("ArchetypePool.zig");
const PR = @import("../registries/PoolRegistry.zig");
const PM = @import("PoolManager.zig");
const CR = @import("../registries/ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");

pub fn PoolInterfaceType(comptime pool_name: PR.PoolName) type {
    return struct {
        const Self = @This();
        const Pool = PR.getPoolFromName(pool_name);

        pool: *Pool,
        entity_manager: *EM.EntityManager,

        /// EntityBuilder type for creating entities in this pool
        /// Required components are non-optional fields
        /// Optional components are nullable fields with null defaults
        pub const Builder = Pool.Builder;

        pub fn init(pool: *Pool, entity_manager: *EM.EntityManager) Self{
            return Self{
                .pool = pool,
                .entity_manager = entity_manager,
            };
        }

        pub fn createEntity(self: *Self, comptime component_data: Builder) !EM.Entity {
            const pool_mask = @TypeOf(self.pool.*).pool_mask;
            var entity_slot = try self.entity_manager.getNewSlot(undefined, pool_mask, undefined);

            const result = try self.pool.addEntity(entity_slot.getEntity(), component_data);
            entity_slot.storage_index = result.storage_index;
            entity_slot.mask_list_index = result.archetype_index;
            entity_slot.pool_name = Pool.NAME;

            return entity_slot.getEntity();
        }

        pub fn destroyEntity(self: *Self, entity: EM.Entity) !void {
            const entity_slot = try self.entity_manager.getSlot(entity);
            const swapped_entity = try self.pool.removeEntity(entity_slot.mask_list_index, entity_slot.storage_index, entity_slot.pool_name);

            if(!std.meta.eql(entity_slot.getEntity(), swapped_entity)) {
                const swapped_slot = try self.entity_manager.getSlot(swapped_entity);
                swapped_slot.storage_index = entity_slot.storage_index;
            }
            try self.entity_manager.remove(entity_slot);
        }

        pub fn getComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !*CR.getTypeByName(component){
            const entity_slot = try self.entity_manager.getSlot(entity);
            return self.pool.getComponent(entity_slot.mask_list_index, entity_slot.storage_index, entity_slot.pool_name, component);
        }

        pub fn hasComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !bool {
            const entity_slot = try self.entity_manager.getSlot(entity);
            return self.pool.hasComponent(entity_slot.mask_list_index, entity_slot.pool_name, component);
        }

        pub fn addComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void {
            const entity_slot = try self.entity_manager.getSlot(entity);
            try self.pool.addOrRemoveComponent(
                entity,
                entity_slot.mask_list_index,
                entity_slot.pool_name,
                entity_slot.storage_index,
                entity_slot.is_migrating,
                .adding,
                component,
                data
            );
            entity_slot.is_migrating = true;
        }

        pub fn removeComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !void {
            const entity_slot = try self.entity_manager.getSlot(entity);
            try self.pool.addOrRemoveComponent(
                entity,
                entity_slot.mask_list_index,
                entity_slot.pool_name,
                entity_slot.storage_index,
                entity_slot.is_migrating,
                .removing,
                component,
                null,
            );
            entity_slot.is_migrating = true;
        }

        pub fn flushMigrationQueue(self: *Self) !void {
            const results = try self.pool.flushMigrationQueue();
            defer self.entity_manager.allocator.free(results);

            for (results) |result| {
                const slot = try self.entity_manager.getSlot(result.entity);

                // Comptime dispatch based on pool type
                if (@hasField(@TypeOf(result), "swapped_entity")) {
                    // ArchetypePool: storage_index changes, handle swapped entity
                    slot.storage_index = result.storage_index;
                    slot.mask_list_index = result.mask_list_index;

                    // Update swapped entity's storage index if a swap occurred
                    if (result.swapped_entity) |swapped| {
                        const swapped_slot = try self.entity_manager.getSlot(swapped);
                        swapped_slot.storage_index = slot.storage_index;
                    }
                } else {
                    // SparseSetPool: storage_index is stable, just update mask info
                    slot.mask_list_index = result.bitmask_index;
                }

                slot.is_migrating = false;
            }
        }
    };
}
