const std = @import("std");
const AP = @import("ArchetypePool.zig");
const PR = @import("PoolRegistry.zig");
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const testing = std.testing;

const EM = @import("EntityManager.zig");
pub fn PoolInterface(comptime components: []const CR.ComponentName, comptime optimize: bool) type {
    return struct {
        const Self = @This();
        pool: *AP.ArchetypePool(components, optimize),
        enitity_manager: *EM.EntityManager,

        pub fn init(pool: *AP.ArchetypePool(components, optimize), entity_manager: *EM.EntityManager) Self{
            return Self{
                .pool = pool,
                .enitity_manager = entity_manager,
            };
        }

        pub fn createEntity(self: *Self, comptime component_data: anytype) !EM.Entity {
            var entity_slot = try self.enitity_manager.getNewSlot(undefined, self.pool.getPoolMask(), undefined);
            const result = try self.pool.addEntity(entity_slot.getEntity(), component_data);
            entity_slot.storage_index = result.index;
            entity_slot.mask = result.mask;
            return entity_slot.getEntity();
        }

        // pub fn destroyEntity(self: *Self, entity: EM.Entity) !void {
        //
        // }

        pub fn addComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName, data: CR.getTypeByName(component)) !void {
            var entity_slot = try self.enitity_manager.getSlot(entity);
            const result = try self.pool.addComponent(entity_slot.mask, entity_slot.storage_index, component, data);
            const old_storage_index = entity_slot.storage_index;
            entity_slot.mask = result.added_entity_mask;
            entity_slot.storage_index = result.added_entity_index;

            std.debug.print("\nEnt Swapped:{} \n", .{result.swaped_entity});

            if(!std.meta.eql(result.swaped_entity, entity)) {
                const swaped_slot = try self.enitity_manager.getSlot(result.swaped_entity);
                swaped_slot.storage_index = old_storage_index;
            }
        }

        // pub fn removeComponent(self: *Self, entity: EM.Entity, comptime component: CR.ComponentName) !void {
        //
        // }
    };
}

test "create entity" {
    var entity_maanger = try EM.EntityManager.init(testing.allocator);
    const MovementPool = AP.ArchetypePool(&.{.Position, .Velocity}, false);
    var movement_pool = try MovementPool.init(testing.allocator);

    defer {
        entity_maanger.deinit();
        movement_pool.deinit();
    }

    var interface = PoolInterface(MovementPool.COMPONENTS, false).init(&movement_pool, &entity_maanger);

    const entity1 = try interface.createEntity(.{
        .Position = .{.x = 3, .y = 4}
    });

    std.debug.print("\nEnt1: {}", .{entity1});

    const entity2 = try interface.createEntity(.{
        .Position = .{.x = 1, .y = 0},
    });

    std.debug.print("\nEnt2: {}", .{entity2});

    try interface.addComponent( 
        entity1,
        .Velocity,
        .{.dx = 1, .dy = 2},
    );
    
    std.debug.print("\nAdding componet to ent2", .{});
    std.debug.print("\nEnt1: {}", .{try interface.enitity_manager.getSlot(entity1)});
    std.debug.print("\nEnt2: {}", .{try interface.enitity_manager.getSlot(entity2)});
}
