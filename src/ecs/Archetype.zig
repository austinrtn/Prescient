const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("ComponentRegistry.zig");

pub const ComponentArrayInterface = struct {
    ptr: *anyopaque,
    addEntityFn: *const fn(*anyopaque, std.mem.Allocator, entity: usize) anyerror!void,
    removeEntityFn: *const fn(*anyopaque, entity: usize) void,
    name: []const u8,
    hash: u64,

    pub fn addEntity(self: *ComponentArrayInterface, allocator: std.mem.Allocator, entity: usize) anyerror!void {
        try self.addEntityFn(self.ptr, allocator, entity);
    }

    pub fn removeEntity(self: *ComponentArrayInterface, entity: usize) void {
        self.removeEntityFn(self.ptr, entity);
    }
};

fn ComponentArray(meta_data: CR.ComponentMetaData) type {
    return struct {
        const Self = @This();

        name: []const u8 = meta_data.name,
        hash: u64 = meta_data.type_hash,
        comp_type: type = meta_data.comp_type,
        list: ArrayList(meta_data.comp_type) = .{},

        pub fn addEntity(self: *Self, allocator: std.mem.Allocator, entity: usize, component_data: meta_data.comp_type) !void {
            try self.list.append(allocator, entity);
            self.list.items[entity] = component_data;
        }

        pub fn removeEntity(self: *Self, entity: usize) void {
            _ = self.list.swapRemove(entity);
        }

        pub fn virtualAddEntity(ptr: *anyopaque, allocator: std.mem.Allocator, entity: usize) anyerror!void {
            const self: *Self  = @ptrCast(ptr);
            Self.addEntity(self, allocator, entity);
        }

        pub fn virtualRemoveEntity(ptr: *anyopaque, allocator: std.mem.Allocator, entity: usize) anyerror!void {
            const self: *Self  = @ptrCast(ptr);
            Self.removeEntity(self, allocator, entity);
        }

        pub fn toInterface(self: *Self) ComponentArrayInterface {
            return .{
                .ptr = @ptrCast(self),
                .addEntityFn = @ptrCast(&Self.addEntity),
                .removeEntityFn = @ptrCast(&Self.removeEntity),
                .name = self.name,
                .hash = self.hash,
            };
        }
    };
}

pub const Archetype = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    signature: u64,
    component_ids: []const u64,
    entities: ArrayList(usize),
    component_arrays: ArrayList(ComponentArrayInterface),

    pub fn init(allocator: std.mem.Allocator, component_ids: []const u64) !Self {
        var component_arrays: ArrayList(ComponentArrayInterface) = .empty;
        try component_arrays.ensureTotalCapacity(allocator, component_ids.len);

        for(component_ids) |id| {
            const meta_data = CR.ComponentRegistry.getMetaData(id);
            const CompArrayType = ComponentArray(meta_data);

            // Allocate and initialize the concrete component array
            var comp_array = try allocator.create(CompArrayType);
            comp_array.* = .{
                .list = .empty,
            };

            // Convert to interface and store
            try component_arrays.append(allocator, comp_array.toInterface());
        }

        return Self {
            .allocator = allocator,
            .signature = std.hash.Murmur2_64.hash(std.mem.asBytes(component_ids)),
            .component_ids = component_ids,
            .entities = .empty,
            .component_arrays = component_arrays,
        };
    }

    pub fn addEntity(self: *Self, entity: usize) !void {
        try self.entities.append(self.allocator, entity);
        for(self.component_arrays.items) |*comp_array| {
            try comp_array.addEntity(self.allocator, entity);
        }
    }

    pub fn removeEntity(self: *Self, entity: usize) void {
        _ = self.entities.swapRemove(entity);
        for(self.component_arrays.items) |*comp_array| {
            comp_array.removeEntity(entity);
        }
    }

    pub fn getEntityComponentData(self: *Self, entity: usize, comptime component_name: CR.ComponentName) CR.getTypeByName(component_name) {
        const hash = CR.ComponentRegistry.hashComponentData(component_name);
        for(self.component_arrays.items) |component_array| {
            if(hash == component_array.hash) {
                // Cast back to the concrete type to access the list
                const CompArrayType = ComponentArray(CR.ComponentMetaData.get(component_name));
                const concrete: *CompArrayType = @alignCast(@ptrCast(component_array.ptr));
                return concrete.list.items[entity];
            }
        }
        unreachable; // Component not found in archetype
    }
};
