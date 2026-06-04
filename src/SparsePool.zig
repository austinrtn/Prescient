const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoArrayHashMapUnmanaged;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Component = CR.Enum;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;
const getBitmask = CR.getBitmaskOfComponents;

pub fn SparsePool(comptime config: PR.Config) type {
    const pool_comps = config.components;
    const Storage = ComponentStorage(config.components);
    const StorageFields = std.meta.fields(Storage);
    const TAG = std.meta.stringToEnum(PR.Enum, config.name) orelse unreachable;
    const AppendData = struct{arch_idx: u32, ent_idx: u32};
    const HashMapValue = struct{arch_idx: u32, arch: *ArrayList(u32)};
    
    return struct {
        const Self = @This();
        pub const tag = TAG;
        pub const pool_mask = getBitmask(pool_comps);

        allocator: std.mem.Allocator,
        archetypes: HashMap(CR.BitSet, HashMapValue) = .empty,
        global_ids: ArrayList(u32) = .empty,
        
        comp_storage: Storage = undefined,
        available_indexes: ArrayList(u32) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{ .allocator = allocator };
            inline for(StorageFields) |field| {
                @field(self.comp_storage, field.name) = .empty;
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.global_ids.deinit(self.allocator);
            inline for(StorageFields) |field| {
                @field(self.comp_storage, field.name).deinit(self.allocator);
            }
            for(self.archetypes.values()) |val| {
                val.arch.deinit(self.allocator);
                self.allocator.destroy(val.arch);
            }
            self.archetypes.deinit(self.allocator);
        }

        pub fn addEnt(self: *Self, ent: anytype, slot_id: u32) !AppendData{
            const EntType = @TypeOf(ent);
            const ent_mask = comptime CR.getBitmaskFromEnt(EntType);
            const val = try self.getOrCreateArchetype(ent_mask);
            const arch = val.arch;

            const ent_idx: u32 = @intCast(arch.items.len);
            try arch.append(self.allocator, ent_idx);
            try self.global_ids.append(self.allocator, slot_id);
            
            inline for(std.meta.fields(EntType)) |field| {
                const ent_field = @field(ent, field.name);
                const comp_converted = CR.convertAnomToComponent(ent_field, field.name);
                try @field(self.comp_storage, field.name).append(self.allocator, comp_converted);
            }

            return .{
                .arch_idx = val.arch_idx,
                .ent_idx = ent_idx,
            };
        }

        pub fn getComponent(self: *Self, comptime component: Component, arch_idx: u32, ent_idx: u32) CR.getCompTypeByEnum(component) {
            _ = arch_idx;
            const comp: CR.getCompTypeByEnum(component) = @field(self.comp_storage, @tagName(component)).items[ent_idx];
            return comp;
        }

        const AddComponentReturnType = struct {
            new_arch_idx: u32,
            new_ent_idx: u32,
            swapped_ent_id: ?u32,
            swapped_ent_idx: ?u32, 
        };

        pub fn addComponent(self: *Self, 
            comptime component: Component, 
            comp_data: CR.getCompTypeByEnum(component),
            arch_idx: u32, 
            ent_idx: u32
        ) !AddComponentReturnType {
            const arch = self.archetypes.values()[arch_idx].arch;
            const swapped_ent_idx = arch.swapRemove(ent_idx);
            
            const comp_storrage = &@field(self.comp_storage, @tagName(component));
            const old_mask = self.archetypes.keys()[arch_idx];
            
            const new_mask = CR.addComponentBit(component, old_mask);
            const new_arch = try self.getOrCreateArchetype(new_mask);
            
            try new_arch.arch.append()
            try comp_storrage.append(self.allocator, comp_data);
            
            const result = blk: {
                const swapped = (swapped_ent_idx != ent_idx);
                const swapped_id = if(swapped) self.global_ids.items[swapped_ent_idx] else null;
                const swapped_idx = if(swapped) swapped_ent_idx else null;
                
                break :blk AddComponentReturnType {
                    .new_arch_idx = new_arch.arch_idx,
                    .new_ent_idx = @intCast(new_ent_idx),
                    .swapped_ent_id = swapped_id,
                    .swapped_ent_idx = swapped_idx,
                };
            };
            
            return result;
        }

        pub fn getOrCreateArchetype(self: *Self, ent_mask: CR.BitSet) !HashMapValue {
            const result = try self.archetypes.getOrPut(self.allocator, ent_mask);
            if(!result.found_existing) {
                const arch_ptr = try self.allocator.create(ArrayList(u32));
                arch_ptr.* = .empty;
                result.value_ptr.* = .{
                    .arch = arch_ptr,
                    .arch_idx = @intCast(result.index),
                };
            }
            return result.value_ptr.*;
        }

        pub fn printStorage(self: Self) void {
            inline for(StorageFields) |field| {
                const arch = @field(self.comp_storage, field.name);
                if(arch.items.len > 0) {
                    std.debug.print("{s}: \n", .{field.name});
                    for(arch.items) |comp_data| {
                        std.debug.print("{any} \n", .{comp_data});
                    }
                }
            }
        }

        pub fn printEnts(self: Self) void {
            var it = self.archetypes.iterator();
            while (it.next()) |entry| {
                const mask = entry.key_ptr.*;
                const arch = entry.value_ptr.arch;

                for (arch.items) |ent_idx| {
                    const idx: usize = @intCast(ent_idx);
                    const global_id = if (idx < self.global_ids.items.len) self.global_ids.items[idx] else ent_idx;

                    std.debug.print("ent {d} (id {d}): ", .{ ent_idx, global_id });

                    inline for (pool_comps, 0..) |component, i| {
                        if (i > 0) std.debug.print(" | ", .{});

                        const comp_name = @tagName(component);
                        const has_component = mask.isSet(@intFromEnum(component));

                        if (has_component) {
                            const comp_storage = @field(self.comp_storage, comp_name);
                            if (idx < comp_storage.items.len) {
                                std.debug.print("{s}={any}", .{ comp_name, comp_storage.items[idx] });
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
