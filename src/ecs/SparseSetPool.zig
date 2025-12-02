const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const CR = @import("ComponentRegistry.zig");
const MM = @import("MaskManager.zig");
const EM = @import("EntityManager.zig");
const PR = @import("PoolRegistry.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const Entity = EM.Entity;

fn StorageType(comptime components: []const CR.ComponentName) type {
    const field_count = components.len + 2;
    var fields:[field_count] std.builtin.Type.StructField = undefined;
    
    //~Field: Entities: AL(Entity)
    fields[0] = .{
        .name = "entities",
        .type = ArrayList(?Entity),
        .alignment = @alignOf(ArrayList(?Entity)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:Bitmask_Indx: u32
    fields[1] = .{
        .name = "bitmask_index",
        .type = ArrayList(?u32),
        .alignment = @alignOf(ArrayList(?u32)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:ComponentData: AL(?Component)
    for(components, (field_count - components.len)..) |component, i| {
        const name = @tagName(component);
        const comp_type = CR.getTypeByName(component);
        const T = ArrayList(?comp_type);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
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

pub const PoolConfig = struct {
    name: PR.PoolName,
    req: ?[]const CR.ComponentName,
    opt: ?[]const CR.ComponentName,
};

pub fn SparseSetPoolType(comptime config: PoolConfig) type {
    const req = if(config.req) |req_comps| req_comps else &.{};
    const opt = if(config.opt) |opt_comps| opt_comps else &.{};

    const pool_components = comptime blk: {
        if(req.len == 0 and opt.len == 0) {
            @compileError("\nPool must contain at least one component!\n");
        }

        if(req.len == 0 and opt.len > 0) {
            break :blk opt;
        }

        else if(req.len > 0 and opt.len == 0) {
            break :blk req;
        }

        else {
            break :blk req ++ opt;
        }
    };

    const POOL_MASK = comptime MaskManager.Comptime.createMask(pool_components);
    const Storage = StorageType(pool_components);
    return struct {
        const Self = @This();
        pub const NAME = config.name;
        pub const MASK = POOL_MASK;

        allocator: Allocator,
        storage: Storage,
        masks: ArrayList(struct {
            mask: MaskManager.Mask,
            entities: ArrayList(Entity),
        }),
        empty_indexes: ArrayList(usize),

        pub fn init(allocator: Allocator) Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.masks = .{};
            self.empty_indexes = .{};

            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name) = .{};
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).deinit(self.allocator);
            }
            for (self.masks.items) |*mask_entry| {
                mask_entry.entities.deinit(self.allocator);
            }
            self.masks.deinit(self.allocator);
            self.empty_indexes.deinit(self.allocator);
        }

        pub fn addEntity(self: *Self, entity: EM.Entity) !u32 {
            const index = self.empty_indexes.pop() orelse blk: {
                inline for(std.meta.fields(Storage)) |field| {
                    try @field(self.storage, field.name).append(self.allocator, undefined);
                }
                break :blk self.storage.entities.items.len - 1;
            };

            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[index] = null;
            }
            self.storage.entities.items[index] = entity;
            const bitmask_index = try self.getOrCreateBitmask(0);
            self.storage.bitmask_index.items[index] = bitmask_index;
            try self.masks.items[bitmask_index].entities.append(self.allocator, entity);

            return @intCast(index);
        }

        pub fn removeEntity(self: *Self, storage_index: u32) void {
            const bitmask_index = self.storage.bitmask_index.items[storage_index];
            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[bitmask_index] = null;
            }

            for(self.masks.items[bitmask_index], 0..) |ent, i| {
                if(storage_index == ent) {
                    self.masks.items[bitmask_index].entities:
                }  
            }
        }

        fn getOrCreateBitmask(self: *Self, bitmask: MaskManager.Mask) !u32 {
            for (self.masks.items, 0..) |mask_entry, i| {
                if (mask_entry.mask == bitmask) {
                    return @intCast(i);
                }
            }

            try self.masks.append(self.allocator, .{
                .mask = bitmask,
                .entities = .{}
            });
            return @intCast(self.masks.items.len - 1);
        }
    };
}

test "Basic" {
    const allocator = testing.allocator;
    const SparsePool = SparseSetPoolType(.{ .name = .GeneralPool, .req = null, .opt = std.meta.tags(CR.ComponentName)});
    var pool = SparsePool.init(allocator);
    defer pool.deinit();
    const entity = EM.Entity{.index = 0, .generation = 0};
    _ = try pool.addEntity(entity);
}
