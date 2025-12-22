const std = @import("std");
const PR = @import("PoolRegistry.zig");
const em = @import("EntityManager.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;

const pool_storage_type = blk: {
    var fields: [PR.pool_types.len]std.builtin.Type.StructField = undefined;

    for(PR.pool_types, 0..) |pool, i| {
        const name = @tagName(@as(PR.PoolName,@enumFromInt(i)));
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

pub const PoolManager = struct {
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

        pub fn getOrCreatePool(self: *Self, comptime pool: PR.PoolName) !*PR.getPoolFromName(pool) {
            //Get names of each field for the pool storage
            const field_name = @tagName(pool);
            inline for(std.meta.fields(@TypeOf(self.storage))) |field| {
                //Check if pool name matches field - must be comptime comparison
                if(comptime std.mem.eql(u8, field.name, field_name)) {
                    if(@field(self.storage, field.name)) |pool_ptr|{
                        return pool_ptr;
                    }
                    else {
                        const ptr = try self.allocator.create(PR.getPoolFromName(pool));
                        ptr.* = try PR.getPoolFromName(pool).init(self.allocator);
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
            inline for(0..PR.pool_types.len) |i| {
                const pool_enum:PR.PoolName = @enumFromInt(i);
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

                // Comptime dispatch based on pool type
                if (@hasField(@TypeOf(result), "swapped_entity")) {
                    // ArchetypePool: storage_index changes, handle swapped entity
                    const storage_index_holder = slot.storage_index;
                    slot.mask_list_index = result.mask_list_index;
                    slot.storage_index = result.storage_index;

                    if(result.swapped_entity) |swapped_ent| {
                        const swapped_slot = try entity_manager.getSlot(swapped_ent);
                        swapped_slot.storage_index = storage_index_holder;
                    }
                } else {
                    // SparseSetPool: storage_index is stable, just update mask info
                    slot.mask_list_index = result.bitmask_index;
                }

                slot.is_migrating = false;
            }
        }

        pub fn flushNewAndReallocatingLists(self: *Self) void {
            inline for(0..PR.pool_types.len) |i| {
                const pool_enum:PR.PoolName = @enumFromInt(i);
                const name = @tagName(pool_enum);

                const storage_field = @field(self.storage, name);
                if(storage_field) |pool| {
                    pool.flushNewAndReallocatingLists();
                }
            }
        }
};

test "flushAllPools" {
    const allocator = std.testing.allocator;

    var entity_manager = try em.EntityManager.init(allocator);
    var pool_manager = PoolManager.init(allocator);
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
    try std.testing.expect(!MaskManager.maskContains(mask_before, MaskManager.Comptime.componentToBit(.Velocity)));

    // Queue a migration to add Velocity
    try iface.addComponent(entity, .Velocity, .{ .dx = 5.0, .dy = 10.0 });

    // Flush all pools and verify entity was updated
    try pool_manager.flushAllPools(&entity_manager);

    const slot_after = try entity_manager.getSlot(entity);
    const mask_after = movement_pool.mask_list.items[slot_after.mask_list_index];
    try std.testing.expect(MaskManager.maskContains(mask_after, MaskManager.Comptime.componentToBit(.Velocity)));
}
