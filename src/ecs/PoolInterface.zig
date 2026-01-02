const std = @import("std");
const AP = @import("ArchetypePool.zig");
const PR = @import("../registries/PoolRegistry.zig");
const PM = @import("PoolManager.zig");
const CR = @import("../registries/ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const EOQ = @import("EntityOperationQueue.zig");
const EntityOperationType = EOQ.EntityOperationType;

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

        /// Creates an entity with the given components (deferred).
        /// The entity handle is returned immediately, but the entity won't be
        /// visible in queries until after the next flush.
        pub fn createEntity(self: *Self, component_data: Builder) !EM.Entity {
            // Reserve a pending slot - entity handle is valid but marked pending
            var entity_slot = try self.entity_manager.getNewPendingSlot(Pool.NAME);

            // Queue the actual creation for later
            try self.pool.queueEntityCreate(entity_slot.getEntity(), component_data);

            return entity_slot.getEntity();
        }

        /// Destroys an entity (deferred).
        /// The entity remains accessible until the next flush.
        pub fn destroyEntity(self: *Self, entity: EM.Entity) !void {
            // Use unchecked access since we need to get the slot even if pending
            const entity_slot = try self.entity_manager.getSlotUnchecked(entity);

            // Can't destroy an entity that's already pending destroy
            if (entity_slot.is_pending_destroy) return error.EntityAlreadyPendingDestroy;

            // Can't destroy an entity that hasn't been created yet
            if (entity_slot.is_pending_create) {
                // Entity was created then destroyed in same frame - cancel the create
                // The queueDestroy will handle removing it from create queue
                try self.pool.queueEntityDestroy(entity, 0, 0);
                // Release the slot immediately since entity never existed in storage
                try self.entity_manager.remove(entity_slot);
                return;
            }

            // Queue destruction - entity remains accessible until flush
            try self.pool.queueEntityDestroy(
                entity,
                entity_slot.storage_index,
                entity_slot.mask_list_index
            );
            entity_slot.is_pending_destroy = true;
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

        /// Flush deferred entity operations (create/destroy).
        /// Called by PoolManager before flushMigrationQueue.
        pub fn flushEntityOperations(self: *Self) !void {
            const results = try self.pool.flushEntityOperations();
            defer self.pool.allocator.free(results);

            for (results) |result| {
                switch (result.operation) {
                    .create => {
                        // Finalize the pending slot with actual storage location
                        const slot = try self.entity_manager.getSlotUnchecked(result.entity);
                        EM.EntityManager.finalizePendingSlot(slot, result.mask_list_index, result.storage_index);
                    },
                    .destroy => {
                        const slot = try self.entity_manager.getSlotUnchecked(result.entity);

                        // Update swapped entity if applicable (archetype pools only)
                        if (result.swapped_entity) |swapped| {
                            const swapped_slot = try self.entity_manager.getSlotUnchecked(swapped);
                            swapped_slot.storage_index = slot.storage_index;
                        }

                        // Remove entity from manager
                        try self.entity_manager.remove(slot);
                    },
                }
            }
        }

        pub fn flushMigrationQueue(self: *Self) !void {
            const results = try self.pool.flushMigrationQueue();
            defer self.entity_manager.allocator.free(results);

            for (results) |result| {
                // Use unchecked since entities might have pending flags
                const slot = try self.entity_manager.getSlotUnchecked(result.entity);

                // Comptime dispatch based on pool type
                if (@hasField(@TypeOf(result), "swapped_entity")) {
                    // ArchetypePool: storage_index changes, handle swapped entity
                    slot.storage_index = result.storage_index;
                    slot.mask_list_index = result.mask_list_index;

                    // Update swapped entity's storage index if a swap occurred
                    if (result.swapped_entity) |swapped| {
                        const swapped_slot = try self.entity_manager.getSlotUnchecked(swapped);
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
