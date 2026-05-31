const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;

const getBitmask = CR.getBitmaskOfComponents;
const ArchetypeStorageT = @import("ArchetypeStorage.zig").Archetype;
const Component = CR.Enum;
const CR = ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Config = @import("PoolRegistry.zig").Config;

pub fn EntPool(comptime config: Config) type {
    const pool_comps = config.components;
    const ARCHETYPE = ArchetypeStorageT(pool_comps);
    const TAG = std.meta.stringToEnum(PR.Enum, config.name) orelse unreachable;
    const HashMapValue = struct{arch_idx: u32, arch: *ARCHETYPE};
    const AppendData = struct{arch_idx: u32, ent_idx: u32};

    return struct {
        const Self = @This();
        pub const Archetype = ARCHETYPE;
        pub const tag = TAG;

        pub const pool_mask = getBitmask(pool_comps);
        const HashmapType = struct{CR.BitSet, HashMapValue};

        allocator: std.mem.Allocator,
        archetypes: HashMap(CR.BitSet, HashMapValue) = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{ .allocator = allocator };
            self.archetypes = .init(allocator);
            return self;
        }

        pub fn deinit(self: *Self) void {
            var values = self.archetypes.valueIterator();
            while(values.next()) |val| {
                val.arch.deinit();
                self.allocator.destroy(val.arch);
            }
            self.archetypes.deinit();
        }

        pub fn append(self: *Self, ent: anytype, slot_id: u32) !AppendData {
            const ent_mask = comptime CR.getBitmaskFromEnt(@TypeOf(ent));
            const val = try self.getOrCreateArchetype(ent_mask);
            const arch = val.arch;

            const ent_idx = try arch.append(ent, slot_id);
            return .{.arch_idx = val.arch_idx, .ent_idx = ent_idx};
        }

        pub fn remove(self: *Self, ent: anytype) void  {
            const ent_mask = comptime CR.getBitmaskFromEnt(@TypeOf(ent));
            const val = self.getArchetype(ent_mask);
            const arch = val.arch;

            _ = arch.remove(0);
        }

        pub fn getArchetypesContainingBitset(self: Self, mask: CR.BitSet) ![]CR.BitSet {
            var matches: ArrayList(CR.BitSet) = .empty;
            defer matches.deinit(self.allocator);

            var keys = self.archetypes.keyIterator();

            while(keys.next()) |arch_mask| {
                var temp = arch_mask.intersectWith(mask);
                if(temp.eql(mask)) try matches.append(self.allocator, arch_mask.*);
            }

            return matches.toOwnedSlice(self.allocator);
        }

        pub fn getArchetype(self: *Self, ent_mask: CR.BitSet) HashMapValue {
            return self.archetypes.get(ent_mask) orelse unreachable;
        }

        fn getOrCreateArchetype(self: *Self, ent_mask: CR.BitSet) !HashMapValue {
            const archetype = self.archetypes.get(ent_mask);
            return archetype orelse blk: {
                const arch_ptr = try self.allocator.create(Archetype);
                arch_ptr.* = .init(self.allocator);

                const map_val: HashMapValue = .{.arch_idx = self.archetypes.count(), .arch = arch_ptr};
                try self.archetypes.put(ent_mask, map_val);
                break :blk self.archetypes.get(ent_mask) orelse unreachable;
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
