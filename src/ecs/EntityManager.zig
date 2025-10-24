const std = @import("std");

// const ar = @import("../registries/ArchetypeRegistry.zig"); // TODO: Fix import path

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ComponentRegistry = @import("ComponentRegistry.zig");
const ComponentName = ComponentRegistry.ComponentName;
const getComponentByName = ComponentRegistry.GetComponentByName;
const Mask = ComponentRegistry.ComponentMask;

pub const EntityManagerErrors = error{NoAvailableEntities};

pub const Entity = struct {
    index: u32,
    generation: u32,
};

pub const EntitySlot = struct {
    index: u32,
    generation: u32 = 0,
    pool_siganture: u64 = undefined,
    mask: Mask = undefined,
    storage_index: u32 = undefined,

    pub fn getEntity(self: *@This()) Entity {
        return .{.index = self.index, .generation = self.generation};
    }
};

pub const EntityManager = struct {
    const Self = @This();

    allocator: Allocator,
    entitySlots: ArrayList(EntitySlot),
    availableEntities: ArrayList(usize),

    pub fn init(allocator: Allocator, archetypeManager: *ar.ArchetypeManager) !Self {
        const entityManager: Self = .{
            .allocator = allocator,
            .entitySlots = .{},
            .availableEntities = .{},
            .archetypeManager = archetypeManager,
        };

        return entityManager;
    }

    pub fn getSlot(self: *Self, entity: Entity) !*EntitySlot {
        const slot = &self.entitySlots.items[entity.index];
        if(slot.generation != entity.generation) return error.StaleEntity;
        return slot;
    }

    pub fn getNewSlot(self: *Self) !*EntitySlot{
        const index = if(self.availableEntities.pop()) |indx|
            indx
        else blk: {
            const newIndex = @as(u32, @intCast(self.entitySlots.items.len));
            try self.entitySlots.append(self.allocator, .{
                .index = newIndex,
                .archetypeIndex = undefined,
                .archetypeName = undefined,
                .generation = 0,
            });
            break :blk newIndex;
        };

        const slot = &self.entitySlots.items[index];
        return slot;
    }

    pub fn remove(self: *Self, slot: *EntitySlot) !void {
        slot.generation +%= 1;
        try self.availableEntities.append(self.allocator, slot.index);
    }

    pub fn getComponentData(self: *Self, entity: Entity, comptime componentName: ComponentName) !*getComponentByName(componentName) {
        const slot = try self.getSlot(entity);
        inline for(std.meta.fields(ar.ArchetypeName)) |*field|{
            const archetypeName = @field(ar.ArchetypeName, field.name);
            if(archetypeName == slot.archetypeName) {
                const archetype = self.archetypeManager.get(archetypeName);
                return archetype.getComponentData(componentName, slot.archetypeIndex);
            }
        }
        unreachable;
    }

    pub fn deinit(self: *Self) void {
        self.entitySlots.deinit(self.allocator);
        self.availableEntities.deinit(self.allocator);
    }
};
