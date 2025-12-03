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
const EB = @import("EntityBuilder.zig");
const EntityBuilderType = EB.EntityBuilderType;

fn StorageType(comptime components: []const CR.ComponentName) type {
    const field_count = components.len + 2;
    var fields:[field_count] std.builtin.Type.StructField = undefined;
    
    //~Field: entities: AL(Entity)
    fields[0] = .{
        .name = "entities",
        .type = ArrayList(?Entity),
        .alignment = @alignOf(ArrayList(?Entity)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:bitmask_index: u32
    fields[1] = .{
        .name = "bitmask_index",
        .type = ArrayList(?u32),
        .alignment = @alignOf(ArrayList(?u32)),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    //~Field:component: AL(?Component)
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
    const Builder = EntityBuilderType(req, opt);

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

        pub fn addEntity(self: *Self, entity: EM.Entity, comptime component_data: Builder) !u32 {
            const components = comptime EB.getComponentsFromData(pool_components, Builder, component_data); 
            const bitmask = MaskManager.Comptime.createMask(components);

            const Storage_index = self.empty_indexes.pop() orelse blk: {
                inline for(std.meta.fields(Storage)) |field| {
                    try @field(self.storage, field.name).append(self.allocator, null);
                }
                break :blk self.storage.entities.items.len - 1;
            };

            inline for(components) |component| {
                const T = CR.getTypeByName(component);
                const field_value = @field(component_data, @tagName(component));

                // Unwrap optional if needed
                const data = comptime blk: {
                    const field_info = for (std.meta.fields(Builder)) |f| {
                        if (std.mem.eql(u8, f.name, @tagName(component))) break f;
                    } else unreachable;

                    const is_optional = @typeInfo(field_info.type) == .optional;
                    if (is_optional) {
                        break :blk field_value.?; // Unwrap the optional
                    } else {
                        break :blk field_value; // Already non-optional
                    }
                };

                const typed_data = if (@TypeOf(data) == T)
                    data
                else blk: {
                    var result: T = undefined;
                    inline for(std.meta.fields(T)) |field| {
                        if(!@hasField(@TypeOf(data), field.name)) {
                            @compileError("Field " ++ field.name ++ " is missing from component "
                                ++ @tagName(component) ++ "!\nMake sure fields of all components are included and spelled properly when using Pool.createEntity()\n");
                        }
                        @field(result, field.name) = @field(data, field.name);
                    }
                    break :blk result;
                };
                @field(self.storage, @tagName(component)).items[Storage_index] = typed_data;
            }

            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[Storage_index] = null;
            }

            self.storage.entities.items[Storage_index] = entity;
            const bitmask_index = try self.getOrCreateBitmask(bitmask);
            self.storage.bitmask_index.items[Storage_index] = bitmask_index;
            try self.masks.items[bitmask_index].entities.append(self.allocator, entity);

            return @intCast(Storage_index);
        }

        fn getEntityMetadata(self: *Self, storage_index: u32) struct { Entity, MaskManager.Mask, usize } {
            const mask_index: usize = @intCast(self.storage.bitmask_index.items[storage_index].?);
            return .{
                self.storage.entities.items[storage_index].?,
                self.masks.items[mask_index].mask,
                mask_index,
            };
        }

        fn removeFromMaskList(self: *Self, entity: EM.Entity, bitmask_index: usize) void {
            for(self.masks.items[bitmask_index].entities.items, 0..) |ent, i| {
                if(entity.index == ent.index) {
                    _ = self.masks.items[bitmask_index].entities.swapRemove(i);
                    return;
                }  
            }
        }

        pub fn removeEntity(self: *Self, storage_index: u32) void {
            const entity, _, 
            const bitmask_index = self.getEntityMetadata(storage_index);

            inline for(std.meta.fields(Storage)) |field| {
                @field(self.storage, field.name).items[storage_index] = null;
            }
            self.removeFromMaskList(entity, bitmask_index);
        }

        pub fn addComponent(self: *Self, storage_index: u32, comptime component:CR.ComponentName, value: CR.getTypeByName(component)) !void {
            const entity, const bitmask, const bitmask_index = self.getEntityMetadata(storage_index);
            const new_bitmask = MaskManager.Comptime.addComponent(bitmask, component);
            const comp_storage = &@field(self.storage, @tagName(component)).items[storage_index];            
            if(comp_storage.* != null) return error.EntityAlreadyHasComponent;

            self.removeFromMaskList(entity, bitmask_index);
           
            const new_bitmask_index = try self.getOrCreateBitmask(new_bitmask);
            try self.masks.items[new_bitmask_index].entities.append(self.allocator, entity);
            self.storage.bitmask_index.items[storage_index] = new_bitmask_index;

            comp_storage.* = value; 
        }

        pub fn removeComponent(self: *Self, storage_index: u32, comptime component:CR.ComponentName) !void {
            const entity, const bitmask, const bitmask_index = self.getEntityMetadata(storage_index);
            const new_bitmask = MaskManager.Comptime.removeComponent(bitmask, component);
            const comp_storage = &@field(self.storage, @tagName(component)).items[storage_index];  

            if(comp_storage.* == null) return error.EntityDoesNotHaveComponent;
            self.removeFromMaskList(entity, bitmask_index);
           
            const new_bitmask_index = try self.getOrCreateBitmask(new_bitmask);
            try self.masks.items[new_bitmask_index].entities.append(self.allocator, entity);
            self.storage.bitmask_index.items[storage_index] = new_bitmask_index;
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

    const entity = EM.Entity{.index = 3, .generation = 0};
    const ent = try pool.addEntity(entity, .{.Position = .{.x = 1, .y = 4}});

    try pool.addComponent(ent, .Velocity, .{.dx = 0, .dy = 0});
    try pool.removeComponent(ent, .Velocity);
}
