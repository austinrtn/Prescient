const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoArrayHashMapUnmanaged;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;
const getBitmask = CR.getBitmaskOfComponents;

pub fn SparsePool(comptime config: PR.Conifg) type {
    const pool_comps = config.components;
    const Storage = ComponentStorage(config.components);
    const StorageFields = std.meta.fields(Storage);
    const TAG = std.meta.stringToEnum(PR.Enum, config.name) orelse unreachable;
    
    return struct {
        const Self = @This();
        pub const tag = TAG;
        pub const pool_mask = getBitmask(pool_comps);

        allocator: std.mem.Allocator,
        archetypes: HashMap(CR.BitSet, ArrayList(u32)) = .empty,
        global_ids: ArrayList(u32) = .empty,
        
        comp_storage: Storage = undefined,
        available_indexes: ArrayList(u32) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            const self: Self = .{ .allocator = allocator };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.global_ids.deinit(self.allocator);
            self.archetypes.deinit(self.allocator);
            inline for(StorageFields) |field| {
                @field(self.comp_storage, field.name).deinit(self.allocator);
            }
        }

        pub fn addEnt(self: *Self, ent: anytype, slot_id: u32) !u32 {
            const EntType = @TypeOf(ent);
            const ent_mask = comptime CR.getBitmaskFromEnt(EntType);
            const arch = try self.getOrCreateArchetype(ent_mask);

            const ent_idx = arch.items.len;
            try arch.append(self.allocator, ent_idx);
            try self.global_ids.append(self.allocator, slot_id);
            
            inline for(std.meta.fields(EntType)) |field| {
                @field(self.comp_storage, field.name) = @field(ent, field.name);
            }

            return ent_idx;
        }

        pub fn getOrCreateArchetype(self: *Self, ent_mask: CR.BitSet) !*ArrayList(u32) {
            const result = try self.archetypes.getOrPut(self.allocator, ent_mask);
            return result.value_ptr;
        }
    };
}
