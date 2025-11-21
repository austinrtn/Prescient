const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const ArchPool = @import("ArchetypePool.zig");
const em = @import("EntityManager.zig");
const mm = @import("MaskManager.zig");

/// Basic movement pool for entities that can move
/// Required: (none)
/// Optional: Position, Velocity
pub const MovementPool = ArchPool.ArchetypePool(&.{}, &.{.Position, .Velocity}, .MovementPool);

/// Enemy entities with combat and AI capabilities
/// Required: (none)
/// Optional: Position, Velocity, Attack, Health, AI
pub const EnemyPool = ArchPool.ArchetypePool(&.{}, &.{.Position, .Velocity, .Attack, .Health, .AI}, .EnemyPool);

/// Player entities - must have a position
/// Required: Position
/// Optional: Health, Attack, Sprite, Player
pub const PlayerPool = ArchPool.ArchetypePool(&.{.Position}, &.{.Health, .Attack, .Sprite, .Player}, .PlayerPool);

/// Renderable entities that can be drawn to screen
/// Required: Position, Sprite
/// Optional: Velocity
pub const RenderablePool = ArchPool.ArchetypePool(&.{.Position, .Sprite}, &.{.Velocity}, .RenderablePool);

/// Combat entities that can fight
/// Required: Health, Attack
/// Optional: AI
pub const CombatPool = ArchPool.ArchetypePool(&.{.Health, .Attack}, &.{.AI}, .CombatPool);

pub const PoolName = enum(u32) {
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
    Misc,
};

pub const pool_types = [_]type{
    MovementPool,
    EnemyPool,
    PlayerPool,
    RenderablePool,
    CombatPool,
};

pub fn getPoolFromName(comptime pool: PoolName) type {
    return pool_types[@intFromEnum(pool)];
}

pub fn PoolManager() type {
    const pool_storage_type = blk: {
        var fields: [pool_types.len]std.builtin.Type.StructField = undefined;
       
        for(pool_types, 0..) |pool, i| {
            const name = @tagName(@as(PoolName,@enumFromInt(i)));
            fields[i] = std.builtin.Type.StructField{
                .name = name,
                .type = ?*pool,
                .alignment = @alignOf(?*pool),
                .default_value_ptr = null,
                .is_comptime = false,
            };
        }

        break :blk @Type(.{
            .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    };

    return struct {
        const Self = @This();

        storage: pool_storage_type, 
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self{
            const storage = blk: {
                var result: pool_storage_type = undefined;
                inline for(std.meta.fields(pool_storage_type)) |field_info| {
                    @field(result, field_info.name) = null;
                }
                break :blk result;
            };
            return .{.allocator = allocator, .storage = storage};
        }
        
        pub fn getOrCreatePool(self: *Self, comptime pool: PoolName) !*getPoolFromName(pool) {
            //Get names of each field for the pool storage
            const field_name = @tagName(pool);
            inline for(std.meta.fields(@TypeOf(self.storage))) |field| {
                //Check if pool name matches field - must be comptime comparison
                if(comptime std.mem.eql(u8, field.name, field_name)) {
                    if(@field(self.storage, field.name)) |pool_ptr|{
                        return pool_ptr;
                    }
                    else {
                        const ptr = try self.allocator.create(getPoolFromName(pool));
                        ptr.* = try getPoolFromName(pool).init(self.allocator);
                        @field(self.storage, field.name) = ptr;
                        return ptr;
                    }
                }
            }
            unreachable;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(@TypeOf(self.storage))) |field| {
                const pool = &@field(self.storage, field.name);
                if(pool.*) |result| {
                    result.*.deinit();
                    self.allocator.destroy(result);
                }
            }
        }

        pub fn flushAllPools(self: *Self, entity_manager: *em.EntityManager) !void {
            inline for(0..pool_types.len) |i| {
                const pool_enum:PoolName = @enumFromInt(i);
                const name = @tagName(pool_enum);

                const storage_field = @field(self.storage, name);
                if(storage_field) |pool| {
                    try Self.flushMigrationQueue(pool, entity_manager);
                }
            }
        } 

        pub fn flushMigrationQueue(pool: anytype, entity_manager: *em.EntityManager) !void {
            const flush_results = try pool.flushMigrationQueue();
            defer pool.allocator.free(flush_results);

            for(flush_results) |result| {
                var slot = try entity_manager.getSlot(result.entity);
                const storage_index_holder = slot.storage_index;

                slot.mask_list_index = result.mask_list_index;
                slot.storage_index = result.archetype_index;

                if(result.swapped_entity) |swapped_ent| {
                    const swapped_slot = try entity_manager.getSlot(swapped_ent);
                    swapped_slot.storage_index = storage_index_holder;
                }
            }
        }
    };
}

test "flushAllPools" {
    const allocator = std.testing.allocator;

    var entity_manager = try em.EntityManager.init(allocator);
    var pool_manager = PoolManager().init(allocator);
    const movement_pool = try pool_manager.getOrCreatePool(.MovementPool);
    defer {
        pool_manager.deinit();
        entity_manager.deinit();
    }

    var iface = movement_pool.getInterface(&entity_manager);

    // Create entity with Position
    const entity = try iface.createEntity(.{ .Position = .{ .x = 10.0, .y = 20.0 } });
    const slot_before = try entity_manager.getSlot(entity);
    const mask_before = movement_pool.mask_list.items[slot_before.mask_list_index];
    try std.testing.expect(!mm.maskContains(mask_before, mm.Comptime.componentToBit(.Velocity)));

    // Queue a migration to add Velocity
    try iface.addComponent(entity, .Velocity, .{ .dx = 5.0, .dy = 10.0 });

    // Flush all pools and verify entity was updated
    try pool_manager.flushAllPools(&entity_manager);

    const slot_after = try entity_manager.getSlot(entity);
    const mask_after = movement_pool.mask_list.items[slot_after.mask_list_index];
    try std.testing.expect(mm.maskContains(mask_after, mm.Comptime.componentToBit(.Velocity)));
}
