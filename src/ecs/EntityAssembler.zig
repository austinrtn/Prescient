const std = @import("std");

const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const ComponentName = ComponentRegistry.ComponentName;
const ComponentNames = ComponentRegistry.ComponentNames;
const GetComponentByName = ComponentRegistry.GetComponentByName;

const Archetype = @import("Archetype.zig");
const ArchetypeTemplate = @import("ArchetypeTemplate.zig").ArchetypeTemplate;
const EntityManager = @import("EntityManager.zig").EntityManager;
const Entity = @import("EntityManager.zig").Entity;

pub fn EntityAssembler(comptime componentNames: []const ComponentName) type {
    return struct {
        const Self = @This();
        archetype: *Archetype.Archetype(componentNames),
        archetypeTemplate: ArchetypeTemplate(componentNames),
        entityManager: *EntityManager,

        pub fn init(entityManager: *EntityManager) !Self {
            return .{
                .archetypeTemplate = ArchetypeTemplate(componentNames){},
                .archetype = entityManager.archetypeManager.queryComponent(componentNames),
                .entityManager = entityManager,
            };
        }

        pub fn setComponent(self: *Self, comptime componentName: ComponentName, data: GetComponentByName(componentName)) void {
            self.archetypeTemplate.set(componentName, data);
        }

        pub fn createEntity(self: *Self) !Entity {
            if(!self.isCompletelyAssembled()) {
                std.debug.print("\nentityAssembler is incomplete.  All components in entityAssembler must be set before creating entity.\n", .{});
                return error.UndefinedComponentsInEntityAssembler;
            }

            const slot = try self.entityManager.getNewSlot();
            const entity = slot.getEntity();
            const archetypeIndex = try self.archetype.addEntity(slot.index, self.archetypeTemplate);
            slot.archetypeIndex = archetypeIndex;

            const ar = @import("../registries/ArchetypeRegistry.zig");
            const ArchetypeType = @TypeOf(self.archetype.*);
            const archetypeName = std.meta.stringToEnum(ar.ArchetypeName, ArchetypeType.componentSignature) orelse return error.InvalidArchetypeName;
            slot.archetypeName = archetypeName;

            return entity;
        }

        pub fn destroyEntity(self: *Self, entity: Entity) !void {
            const slot = try self.entityManager.getSlot(entity);

            const swappedSlotIndex = try self.archetype.removeEntity(slot.archetypeIndex);
            const slotToUpdate = &self.entityManager.entitySlots.items[swappedSlotIndex];
            slotToUpdate.archetypeIndex = slot.archetypeIndex;

            try self.entityManager.remove(slot);
        }

        pub fn getComponentData(self: *Self, entity: Entity, comptime componentName: ComponentName) !GetComponentByName(componentName) {
            const slot = try self.entityManager.getSlot(entity);
            return try self.archetype.getComponentData(slot.archetypeIndex, componentName);
        } 

        pub fn isCompletelyAssembled(self: *Self) bool {
            return self.archetypeTemplate.isComplete();
        }
    };
}
