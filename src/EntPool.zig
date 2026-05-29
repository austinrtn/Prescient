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

    return struct {
        const Self = @This();
        pub const Archetype = ArchetypeStorageT(pool_comps);
        pub const tag = std.meta.stringToEnum(PR.Enum, config.name);
        
        pub const pool_mask = getBitmask(pool_comps);
        const HashmapType = struct{CR.BitSet, Archetype};

        allocator: std.mem.Allocator,
        archetypes: HashMap(CR.BitSet, Archetype) = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{ .allocator = allocator };
            self.archetypes = .init(allocator);
            return self;
        }

        pub fn deinit(self: *Self) void {
            var values = self.archetypes.valueIterator();
            while(values.next()) |arch| {
                arch.deinit();
            }
            self.archetypes.deinit();
        }

        pub fn append(self: *Self, ent: anytype) !void {
            const EntType = @TypeOf(ent);
            const ent_comps = comptime CR.getComponentsFromType(EntType);
            const ent_mask = comptime getBitmask(&ent_comps);
            const arch = try self.getOrCreateArchetype(ent_mask);

            try arch.append(ent);
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

        pub fn getArchetype(self: *Self, ent_mask: CR.BitSet) *Archetype {
            return self.archetypes.getPtr(ent_mask) orelse unreachable;
        }

        fn getOrCreateArchetype(self: *Self, ent_mask: CR.BitSet) !*Archetype {
            const archetype = self.archetypes.getPtr(ent_mask);
            return archetype orelse blk: {
                const new_arch: Archetype = .init(self.allocator);
                try self.archetypes.put(ent_mask, new_arch);
                break :blk self.archetypes.getPtr(ent_mask) orelse unreachable;
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
