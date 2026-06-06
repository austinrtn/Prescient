const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoArrayHashMapUnmanaged;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Component = CR.Enum;
const getBitmask = CR.getBitmaskOfComponents;
const Registry = @import("Registry.zig").Registry;

fn ComponentStorage(comptime components: []const Component) type {
    var names: [components.len][]const u8 = undefined;
    var types: [components.len]type = undefined;
    var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

    for (components, 0..) |comp, i| {
        const CompType = CR.getCompTypeByEnum(comp);
        const ComponentWithOwner = struct {
            value: CompType,
            entity_id: Registry.EntityId,
        };

        names[i] = @tagName(comp);
        types[i] = ArrayList(ComponentWithOwner);
        attrs[i] = .{};
    }

    return @Struct(
        .auto,
        null,
        &names,
        &types,
        &attrs,
    );
}

fn EntityRecord(comptime components: []const Component) type {
    var names: [components.len + 1][]const u8 = undefined;
    var types: [components.len + 1]type = undefined;
    var attrs: [components.len + 1]std.builtin.Type.StructField.Attributes = undefined;

    names[0] = "entity_id";
    types[0] = Registry.EntityId;
    attrs[0] = .{};

    for (components, 1..) |comp, i| {
        names[i] = @tagName(comp);
        types[i] = ?Registry.ComponentIndex;
        attrs[i] = .{};
    }

    return @Struct(
        .auto,
        null,
        &names,
        &types,
        &attrs,
    );
}

pub fn SparseSetPool(comptime config: PR.Config) type {
    const pool_comps = config.components;
    const Storage = ComponentStorage(config.components);
    const StorageFields = std.meta.fields(Storage);
    const EntityRecordType = EntityRecord(config.components);
    const TAG = std.meta.stringToEnum(PR.Enum, config.name) orelse unreachable;
    const AppendData = struct { group_index: Registry.GroupIndex, member_index: Registry.MemberIndex };
    const HashMapValue = struct { group_index: Registry.GroupIndex, group: *ArrayList(Registry.RecordIndex) };

    return struct {
        const Self = @This();
        pub const tag = TAG;
        pub const pool_mask = getBitmask(pool_comps);

        allocator: std.mem.Allocator,
        groups: HashMap(CR.BitSet, HashMapValue) = .empty,
        entity_records: ArrayList(EntityRecordType) = .empty,

        comp_storage: Storage = undefined,
        available_indexes: ArrayList(Registry.RecordIndex) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{ .allocator = allocator };
            inline for (StorageFields) |field| {
                @field(self.comp_storage, field.name) = .empty;
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.entity_records.deinit(self.allocator);
            inline for (StorageFields) |field| {
                @field(self.comp_storage, field.name).deinit(self.allocator);
            }

            for (self.groups.values()) |val| {
                val.group.deinit(self.allocator);
                self.allocator.destroy(val.group);
            }
            self.groups.deinit(self.allocator);
        }

        pub fn addEnt(self: *Self, ent: anytype, entity_id: Registry.EntityId) !AppendData {
            const EntType = @TypeOf(ent);
            const entity_mask = comptime CR.getBitmaskFromEnt(EntType);
            const val = try self.getOrCreateArchetype(entity_mask);
            const group = val.group;

            const record_idx: Registry.RecordIndex = .init(self.entity_records.items.len);
            const member_idx: Registry.MemberIndex = .init(group.items.len);
            try group.append(self.allocator, record_idx);

            var entity_record: EntityRecordType = undefined;
            entity_record.entity_id = entity_id;
            inline for (pool_comps) |comp| @field(entity_record, @tagName(comp)) = null;

            inline for (std.meta.fields(EntType)) |field| {
                const ent_field = @field(ent, field.name);
                const comp_converted = CR.convertAnomToComponent(ent_field, field.name);
                const comp_store = &@field(self.comp_storage, field.name);
                try comp_store.append(self.allocator, .{ .value = comp_converted, .entity_id = entity_id });

                @field(entity_record, field.name) = Registry.ComponentIndex.init(comp_store.items.len - 1);
            }

            try self.entity_records.append(self.allocator, entity_record);

            return .{
                .group_index = val.group_index,
                .member_index = member_idx,
            };
        }

        pub fn getComponent(self: *Self, comptime component: Component, group_index: Registry.GroupIndex, member_index: Registry.MemberIndex) CR.getCompTypeByEnum(component) {
            const comp_name = @tagName(component);
            const group = self.groups.values()[group_index.idx()].group;

            const record_idx = group.items[member_index.idx()];
            const entity_record = self.entity_records.items[record_idx.idx()];
            const comp_idx = @field(entity_record, comp_name).?;

            const comp_store = @field(self.comp_storage, @tagName(component));
            return comp_store.items[comp_idx.idx()].value;
        }

        const AddComponentReturnType = struct {
            new_group_index: Registry.GroupIndex,
            new_member_index: Registry.MemberIndex,
            swapped_entity_id: ?Registry.EntityId,
            swapped_member_index: ?Registry.MemberIndex,
        };

       pub fn addComponent(self: *Self, comptime component: Component, comp_value: CR.getCompTypeByEnum(component), group_index: Registry.GroupIndex, member_index: Registry.MemberIndex,) !AddComponentReturnType {
            const old_mask = self.groups.keys()[group_index.idx()];
            const group = self.groups.values()[group_index.idx()].group;
            const member_idx = member_index.idx();
            const record_idx = group.items[member_idx];
            const entity_record = &self.entity_records.items[record_idx.idx()];

            const had_swapped_member = member_idx != group.items.len - 1;
            const swapped_record_idx = if (had_swapped_member) group.items[group.items.len - 1] else null;
            _ = group.swapRemove(member_idx);

            const comp_store = &@field(self.comp_storage, @tagName(component));

            const new_mask = CR.addComponentBit(component, old_mask);
            const new_group = try self.getOrCreateArchetype(new_mask);

            const new_member_idx: Registry.MemberIndex = .init(new_group.group.items.len);
            try comp_store.append(self.allocator, .{ .value = comp_value, .entity_id = entity_record.entity_id });

            try new_group.group.append(self.allocator, record_idx);
            @field(entity_record.*, @tagName(component)) = Registry.ComponentIndex.init(comp_store.items.len - 1);

            const result = blk: {
                const swapped_ent_id = if (swapped_record_idx) |idx| self.entity_records.items[idx.idx()].entity_id else null;
                const swapped_member_idx = if (swapped_record_idx != null) member_index else null;

                break :blk AddComponentReturnType{
                    .new_group_index = new_group.group_index,
                    .new_member_index = new_member_idx,
                    .swapped_entity_id = swapped_ent_id,
                    .swapped_member_index = swapped_member_idx,
                };
            };

            return result;
        }

        pub fn getOrCreateArchetype(self: *Self, ent_mask: CR.BitSet) !HashMapValue {
            const result = try self.groups.getOrPut(self.allocator, ent_mask);
            if (!result.found_existing) {
                const group_ptr = try self.allocator.create(ArrayList(Registry.RecordIndex));
                group_ptr.* = .empty;
                result.value_ptr.* = .{
                    .group = group_ptr,
                    .group_index = .init(result.index),
                };
            }
            return result.value_ptr.*;
        }

        pub fn printStorage(self: Self) void {
            inline for (StorageFields) |field| {
                const comp_store = @field(self.comp_storage, field.name);
                std.debug.print("{s}: \n", .{field.name});
                if (comp_store.items.len > 0) {
                    for (comp_store.items) |comp_value| {
                        std.debug.print("{any} \n", .{comp_value});
                    }
                } else {
                    std.debug.print("N.A\n", .{});
                }
            }
        }

        pub fn printEnts(self: Self) void {
            var it = self.groups.iterator();
            while (it.next()) |entry| {
                const mask = entry.key_ptr.*;
                const group = entry.value_ptr.group;

                std.debug.print("{any}\n", .{mask});
                for (group.items, 0..) |record_idx, member_idx| {
                    const entity_id = if (record_idx.idx() < self.entity_records.items.len) self.entity_records.items[record_idx.idx()].entity_id.val else record_idx.val;

                    std.debug.print("member {d} (id {d}): ", .{ member_idx, entity_id });

                    inline for (pool_comps, 0..) |component, i| {
                        if (i > 0) std.debug.print(" | ", .{});

                        const comp_name = @tagName(component);
                        const has_component = mask.isSet(@intFromEnum(component));

                        if (has_component) {
                            const comp_storage = @field(self.comp_storage, comp_name);
                            const entity_record = self.entity_records.items[record_idx.idx()];
                            if (@field(entity_record, comp_name)) |comp_idx| {
                                std.debug.print("{s}={any}", .{ comp_name, comp_storage.items[comp_idx.idx()] });
                            } else {
                                std.debug.print("{s}=_", .{comp_name});
                            }
                        } else {
                            std.debug.print("{s}=_", .{comp_name});
                        }
                    }

                    std.debug.print("\n", .{});
                }
            }
        }
    };
}
