const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const Registry = @import("Registry.zig").Registry;

const getBitmask = CR.getBitmaskOfComponents;
const ArchetypeStorageT = @import("ArchetypeStorage.zig").Archetype;
const Component = CR.Enum;
const CR = Registry.Component;

pub fn EntPool(comptime components: []const Component) type {
    const Archetype = ArchetypeStorageT(components);
    const MaskInt = CR.BitSet.empty.mask;

    return struct {
        const Self = @This();
        pub const mask = getBitmask(components);

        allocator: std.mem.Allocator,
        archetypes: HashMap(@TypeOf(MaskInt), Archetype) = undefined,

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
            var arch = try self.getOrCreateArchetype(ent_mask);

            try arch.append(ent);
        }

        fn getOrCreateArchetype(self: *Self, comptime ent_mask: CR.BitSet) !*Archetype {
            const archetype = self.archetypes.getPtr(ent_mask.mask);
            return archetype orelse blk: {
                const new_arch: Archetype = .init(self.allocator);
                try self.archetypes.put(ent_mask.mask, new_arch);
                break :blk self.archetypes.getPtr(ent_mask.mask) orelse unreachable;
            };
        }
    };
}
