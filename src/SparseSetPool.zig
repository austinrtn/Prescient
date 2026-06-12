const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoArrayHashMapUnmanaged;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Component = CR.Enum;
const getBitmask = CR.getBitmaskOfComponents;
const Registry = @import("Registry.zig").Registry;
const EntityId = Registry.EntityId;
const GroupIndex = Registry.GroupIndex;
const MemberIndex = Registry.MemberIndex;
const RecordIndex = Registry.RecordIndex;
const ComponentIndex = Registry.ComponentIndex;

fn ComponentWithOwner(comptime ComponentType: type) type { 
    return struct {
        value: ComponentType,
        record_index: RecordIndex,
    };
}

fn SparseSetStorage(comptime components: []const Component) type {
    var names: [components.len][]const u8 = undefined;
    var types: [components.len]type = undefined;
    var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

    for (components, 0..) |comp, i| {
        const CompType = CR.getCompTypeByEnum(comp);

        names[i] = @tagName(comp);
        types[i] = ArrayList(ComponentWithOwner(CompType));
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

fn EntityRecordType(comptime components: []const Component) type {
    var names: [components.len + 4][]const u8 = undefined;
    var types: [components.len + 4]type = undefined;
    var attrs: [components.len + 4]std.builtin.Type.StructField.Attributes = undefined;

    names[0] = "entity_id";
    types[0] = EntityId;
    attrs[0] = .{};

    names[1] = "group_index";
    types[1] = GroupIndex;
    attrs[1] = .{};
    
    names[2] = "member_index";
    types[2] = MemberIndex;
    attrs[2] = .{};
    
    names[3] = "record_index";
    types[3] = RecordIndex;
    attrs[3] = .{};
    
    for (components, 4..) |comp, i| {
        names[i] = @tagName(comp);
        types[i] = ?ComponentIndex;
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
    const Storage = SparseSetStorage(config.components);
    const StorageFields = std.meta.fields(Storage);
    const EntityRecord = EntityRecordType(config.components);
    const TAG = std.meta.stringToEnum(PR.Enum, config.name) orelse unreachable;
    const AppendData = struct { group_index: GroupIndex, member_index: MemberIndex };
    const GroupEntry = struct { group_index: GroupIndex, group: *ArrayList(RecordIndex) };

    return struct {
        const Self = @This();
        pub const tag = TAG;
        pub const pool_mask = getBitmask(pool_comps);

        allocator: std.mem.Allocator,
        groups: HashMap(CR.BitSet, GroupEntry) = .empty,
        entity_records: ArrayList(EntityRecord) = .empty,
        comp_storage: Storage = undefined,
        count: usize = 0,

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

        pub fn addEnt(self: *Self, ent: anytype, entity_id: EntityId) !AppendData {
            const EntType = @TypeOf(ent);
            const entity_mask = comptime CR.getBitmaskFromEnt(EntType);
            const val = try self.getOrCreateArchetype(entity_mask);
            const group = val.group;

            const record_idx: RecordIndex = .init(self.entity_records.items.len);
            const member_idx: MemberIndex = .init(group.items.len);
            try group.append(self.allocator, record_idx);

            var entity_record: EntityRecord = undefined;
            entity_record.entity_id = entity_id;
            entity_record.group_index = val.group_index;
            entity_record.record_index = record_idx;
            entity_record.member_index = member_idx;
            
            inline for (pool_comps) |comp| @field(entity_record, @tagName(comp)) = null;

            inline for (std.meta.fields(EntType)) |field| {
                const ent_field = @field(ent, field.name);
                const comp_converted = CR.convertAnomToComponent(ent_field, field.name);
                const comp_store = &@field(self.comp_storage, field.name);
                try comp_store.append(self.allocator, .{ .value = comp_converted, .record_index = record_idx});

                @field(entity_record, field.name) = ComponentIndex.init(comp_store.items.len - 1);
            }

            try self.entity_records.append(self.allocator, entity_record);
            self.count += 1;

            return .{
                .group_index = val.group_index,
                .member_index = member_idx,
            };
        }

        pub fn removeEnt(self: *Self, group_index: GroupIndex, member_index: MemberIndex) ?EntityId {
            const group = self.groups.values()[group_index.idx()].group;
            const record_idx = group.items[member_index.idx()];
            const ent_record = self.entity_records.items[record_idx.idx()];

            inline for(pool_comps) |comp| {
                const field_name = @tagName(comp);
                // Need to get actual record struct here v
                const component_index = @field(ent_record, field_name);
                const comp_array = &@field(self.comp_storage, field_name);

                if(component_index) |comp_index| {
                    const last_comp_index = comp_array.items.len - 1;
                    const swapped_comp = comp_index.idx() != last_comp_index;
                    if(swapped_comp) {
                        const comp_with_owner = comp_array.items[last_comp_index];
                        const record_of_swapped_ent = &self.entity_records.items[comp_with_owner.record_index.idx()];
                        @field(record_of_swapped_ent, field_name) = comp_index;
                    }
                    _ = comp_array.swapRemove(comp_index.idx());
                }
            }

            const swapped_ent_id = blk: {
                const last_idx = group.items.len - 1;
                if(last_idx != member_index.idx()) {
                    const swapped_record_idx =  group.items[last_idx];
                    const swapped_ent_record = &self.entity_records.items[swapped_record_idx.idx()];
                    swapped_ent_record.member_index = member_index;
                    break :blk swapped_ent_record.entity_id;
                }
                else break :blk null;
            };
            
            _ = group.swapRemove(member_index.idx());
            self.count -= 1;
            return swapped_ent_id; 
        }

        pub fn getComponent(self: *Self, comptime component: Component, group_index: GroupIndex, member_index: MemberIndex) CR.getCompTypeByEnum(component) {
            const comp_name = @tagName(component);
            const group = self.groups.values()[group_index.idx()].group;

            const record_idx = group.items[member_index.idx()];
            const entity_record = self.entity_records.items[record_idx.idx()];
            const comp_idx = @field(entity_record, comp_name).?;

            const comp_array = @field(self.comp_storage, @tagName(component));
            return comp_array.items[comp_idx.idx()].value;
        }

        pub fn setComponent(self: *Self, comptime component: Component, component_value: CR.getCompTypeByEnum(component), group_index: GroupIndex, member_index: MemberIndex) void {
            const comp_name = @tagName(component);
            const group = self.groups.values()[group_index.idx()].group;

            const record_idx = group.items[member_index.idx()];
            const ent_record = self.entity_records.items[record_idx.idx()];
            const comp_idx = @field(ent_record, comp_name).?;
            const comp_array = &@field(self.comp_storage, comp_name);
            comp_array.items[comp_idx.idx()].value = component_value;
        }

        const AddComponentReturnType = struct {
            new_group_index: GroupIndex,
            new_member_index: MemberIndex,
            swapped_entity_id: ?EntityId,
            swapped_member_index: ?MemberIndex,
        };

       pub fn addComponent(self: *Self, comptime component: Component, component_value: CR.getCompTypeByEnum(component), entity_id: EntityId, group_index: GroupIndex, member_index: MemberIndex,) !AddComponentReturnType {
            _ = entity_id; // Uneeded for SparseSetPool.addFunction but entity_id parameter is kept to keep api uniform with ArchetypePool.zig
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

            const new_member_idx: MemberIndex = .init(new_group.group.items.len);
            try comp_store.append(self.allocator, .{ .value = component_value, .record_index = entity_record.record_index});

            try new_group.group.append(self.allocator, record_idx);
            @field(entity_record.*, @tagName(component)) = ComponentIndex.init(comp_store.items.len - 1);

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

        pub fn getOrCreateArchetype(self: *Self, ent_mask: CR.BitSet) !GroupEntry {
            const result = try self.groups.getOrPut(self.allocator, ent_mask);
            if (!result.found_existing) {
                const group_ptr = try self.allocator.create(ArrayList(RecordIndex));
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
