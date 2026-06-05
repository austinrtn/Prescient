const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const PoolManager = @import("PoolManager.zig").PoolManager;
const Component = CR.Enum;
const Pool = PR.Enum;
const EntPool = @import("EntPool.zig").EntPool;

pub fn Query(comptime components: []const Component) type {
    const QueryReturnType = CR.GetTypeOfComponents(components, true);
    const q_mask = comptime CR.getBitmaskOfComponents(components);

    const MatchingPools = blk: {
        var names: [PR.Tags.len][]const u8 = undefined;
        var vals: [PR.Tags.len]u8 = undefined;
        var count: usize = 0;

        for (PR.Tags) |pool| {
            // check if ent pool mask bits are contain all bits of the query
            const T = EntPool(PR.getConfigByEnum(pool));
            var temp = T.pool_mask.intersectWith(q_mask);
            if (temp.eql(q_mask)) {
                names[count] = @tagName(pool);
                vals[count] = @intCast(count);
                count += 1;
            }
        }

        break :blk @Enum(
            u8,
            .exhaustive,
            &names[0..count].*,
            &vals[0..count].*,
        );
    };

    const PoolTags = std.meta.tags(MatchingPools);

    return struct {
        const Self = @This();
        pub const Mask = q_mask;

        allocator: std.mem.Allocator,
        pool_manager: *PoolManager,

        pool_index: usize = 0,
        group_index: usize = 0,
        group_masks: []CR.BitSet = &.{},
        pending_mask_search: bool = true,

        query_return: QueryReturnType = undefined,

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PoolManager) !Self {
            var self: Self = .{ .allocator = allocator, .pool_manager = pool_manager };

            inline for (std.meta.fields(QueryReturnType)) |field| {
                @field(self.query_return, field.name) = &.{};
            }

            self.group_masks = try allocator.alloc(CR.BitSet, 0);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.group_masks);
        }

        pub fn query(self: *Self) !?*QueryReturnType {
            if (self.pool_index == PoolTags.len) {
                self.reset();
                return null;
            }

            const pool_tag: Pool = std.meta.stringToEnum(PR.Enum, @tagName(PoolTags[self.pool_index])) orelse unreachable;
            switch (pool_tag) {
                inline else => |tag| {
                    const ent_pool = self.pool_manager.getPool(tag);
                    if (self.pending_mask_search) {
                        const matches = try ent_pool.getArchetypesContainingBitset(Mask);
                        defer self.allocator.free(matches);

                        self.allocator.free(self.group_masks);
                        self.group_masks = try self.allocator.dupe(CR.BitSet, matches);
                        self.pending_mask_search = false;
                    }

                    const group_obj = ent_pool.getArchetype(self.group_masks[self.group_index]);
                    var return_group: QueryReturnType = undefined;

                    inline for (std.meta.fields(QueryReturnType)) |field| {
                        @field(return_group, field.name) = @field(group_obj.group.comp_storage, field.name).items;
                    }

                    self.query_return = return_group;
                    self.group_index += 1;

                    if (self.group_index == self.group_masks.len) {
                        self.group_index = 0;
                        self.pool_index += 1;
                        self.pending_mask_search = true;
                    }

                    return &self.query_return;
                },
            }
        }

        fn reset(self: *Self) void {
            self.group_index = 0;
            self.pool_index = 0;
            self.pending_mask_search = true;
        }
    };
}

fn QueryReturn(comptime components: []const Component) type {
    const QueryReturnT = blk: {
        var names: [components.len][]const u8 = undefined;
        var types: [components.len]type = undefined;
        var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

        for (components, 0..) |comp, i| {
            const T = ArrayList(CR.GetTypeByField(comp));
            names[i] = @tagName(comp);
            types[i] = T;
            attrs[i] = .{};
        }

        break :blk @Struct(
            .auto,
            null,
            &names,
            &types,
            &attrs,
        );
    };

    return struct {
        pub const Type = QueryReturnT;

        fn initQueryReturnType(data: QueryReturnT) void {
            inline for (std.meta.fields(QueryReturnT)) |field| {
                @field(data, field.name) = .empty;
            }
        }

        fn deinit(allocator: std.mem.allocator, data: *QueryReturnT) void {
            inline for (std.meta.fields(QueryReturnT)) |field| {
                @field(data, field.name).deinit(allocator);
            }
        }
    };
}
