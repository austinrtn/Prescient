const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoArrayHashMapUnmanaged;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const getBitmask = CR.getBitmaskOfComponents;

const ArchetypeStorageT = @import("ArchetypeStorage.zig").Archetype;
const PoolComponentT = @import("ComponentSubset.zig").ComponentSubset;
const Config = @import("PoolRegistry.zig").PoolConfig;
const Registry = @import("Registry.zig").Registry;
const EntityId = Registry.EntityId;
const GroupIndex = Registry.GroupIndex;
const MemberIndex = Registry.MemberIndex;

pub fn ArchetypePool(comptime config: Config) type {
    const TAG = std.meta.stringToEnum(PR.Enum, config.name) orelse unreachable;
    const PoolComponentType = PoolComponentT(TAG);
    const ArchetypeType = ArchetypeStorageT(PoolComponentType);
    const GroupEntry = struct { group_index: GroupIndex, group: *ArchetypeType };
    const AppendData = struct { group_index: GroupIndex, member_index: MemberIndex };

    const AddComponentResult = struct {
        new_group_index: GroupIndex,
        new_member_index: MemberIndex,
        swapped_entity_id: ?EntityId,
        swapped_member_index: ?MemberIndex,
    };

    return struct {
        const Self = @This();
        pub const PoolComponent = PoolComponentType;
        pub const Archetype = ArchetypeType;
        pub const tag = TAG;
        pub const pool_mask = getBitmask(PoolComponent.GlobalComponents);

        allocator: std.mem.Allocator,
        groups: HashMap(CR.BitSet, GroupEntry) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            const self: Self = .{ .allocator = allocator };
            return self;
        }

        pub fn deinit(self: *Self) void {
            for (self.groups.values()) |val| {
                val.group.deinit();
                self.allocator.destroy(val.group);
            }
            self.groups.deinit(self.allocator);
        }

        pub fn addEnt(self: *Self, ent: anytype, entity_id: EntityId) !AppendData {
            const ent_mask = comptime CR.getBitmaskFromEnt(@TypeOf(ent));
            const val = try self.getOrCreateArchetype(ent_mask);
            const group = val.group;

            const member_idx = try group.append(ent, entity_id);
            return .{ .group_index = val.group_index, .member_index = member_idx };
        }

        pub fn removeEnt(self: *Self, group_index: GroupIndex, member_index: MemberIndex) ?EntityId {
            const group = self.groups.values()[group_index.idx()].group;
            return group.remove(member_index);
        }

        pub fn getComponent(self: *Self, comptime component: PoolComponent.Enum, group_index: GroupIndex, member_index: MemberIndex) CR.GetComponentTypeByEnum(PoolComponent.globalize(component)) {
            const group = self.getGroupByIndex(group_index).group;
            return group.getComponent(component, member_index);
        }

        pub fn setComponent(self: *Self, comptime component: PoolComponent.Enum, component_value: CR.GetComponentTypeByEnum(PoolComponent.globalize(component)), group_index: GroupIndex, member_index: MemberIndex) void {
            const group = self.getGroupByIndex(group_index).group;
            group.setComponent(component, component_value, member_index);
        }

        pub fn addComponent(
            self: *Self,
            comptime component: PoolComponent.Enum,
            component_value: CR.GetComponentTypeByEnum(PoolComponent.globalize(component)),
            entity_id: EntityId,
            group_index: GroupIndex,
            member_index: MemberIndex,
        ) !AddComponentResult {
            const old_mask = self.groups.keys()[group_index.idx()];
            const new_mask = CR.addComponentBit(PoolComponent.globalize(component), old_mask);

            const group = self.getGroupByIndex(group_index).group;

            // var comp_buf: [PoolComponent.GlobalComponents.len] CR.Enum = undefined;
            // const mask_comps = CR.getComponentsFromMask(new_mask, &comp_buf);

            var comp_value = CR.initMaskToPartialComponentStruct(PoolComponent.GlobalComponents);
            inline for (comptime PoolComponent.Tags) |comp| {
                if (CR.maskContainsComponent(PoolComponent.globalize(comp), new_mask)) {
                    const field = &@field(comp_value, @tagName(comp));
                    if (component != comp) {
                        field.* = self.getComponent(comp, group_index, member_index);
                    } else field.* = component_value;
                }
            }

            const append_res = try self.addEnt(comp_value, entity_id);

            const swapped_ent_id = group.remove(member_index);

            return .{ .new_group_index = append_res.group_index, .new_member_index = append_res.member_index, .swapped_entity_id = swapped_ent_id, .swapped_member_index = member_index };
        }

        pub fn getArchetypesContainingBitset(self: Self, mask: CR.BitSet) ![]CR.BitSet {
            var matches: ArrayList(CR.BitSet) = .empty;
            defer matches.deinit(self.allocator);

            for (self.groups.keys()) |*arch_mask| {
                var temp = arch_mask.intersectWith(mask);
                if (temp.eql(mask)) try matches.append(self.allocator, arch_mask.*);
            }

            return matches.toOwnedSlice(self.allocator);
        }

        pub fn getArchetype(self: *Self, ent_mask: CR.BitSet) GroupEntry {
            return self.groups.get(ent_mask) orelse unreachable;
        }

        pub fn getGroupByIndex(self: *Self, group_index: GroupIndex) GroupEntry {
            return self.groups.values()[group_index.idx()];
        }

        fn getOrCreateArchetype(self: *Self, ent_mask: CR.BitSet) !GroupEntry {
            const archetype = self.groups.get(ent_mask);
            return archetype orelse blk: {
                const arch_ptr = try self.allocator.create(Archetype);
                arch_ptr.* = .init(self.allocator);

                const map_val: GroupEntry = .{ .group_index = .init(self.groups.count()), .group = arch_ptr };
                try self.groups.put(self.allocator, ent_mask, map_val);
                break :blk self.groups.get(ent_mask) orelse unreachable;
            };
        }
    };
}

// pub fn getItems(self: *Self, comptime components: []const Component) !CR.GetTypeOfComponents(components, true) {
//     const SuperArch = CR.GetTypeOfComponents(components, true);
//     const allocator = self.allocator;

//     const comp_mask = comptime getBitmask(components);
//     const arches = try self.getArchetypesContainingBitset(comp_mask);
//     defer allocator.free(arches);

//     var super_arch: SuperArch = undefined;

//     inline for(std.meta.fields(SuperArch)) |field| {
//         var last_count: usize = 0;
//         var count: usize = 0;

//         for(arches) |arch| {
//             last_count = count;
//             count += arch.len;
//             const super_slice = &@field(super_arch, field.name);
//             super_slice = try allocator.realloc(super_slice, count);

//             @memcpy(super_slice[last_count..count], @field(arch, field.name));
//         }
//     }
// }
