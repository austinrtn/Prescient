const std = @import("std");
const ArrayList = std.ArrayList;
const HashMapType = std.AutoArrayHashMapUnmanaged;
const Registry = @import("src/Registry.zig").Registry;
const EntityId = Registry.EntityId;
const ComponentIndex = Registry.ComponentIndex;
const CR = @import("src/ComponentRegistry.zig").ComponentRegistry;
const Component = CR.Enum;
const ComponentStorage = @import("src/ComponentStorage.zig").ComponentStorage;
const EntityRecordType = @import("src/EntityRecord.zig").EntityRecord;
const RecordIndex = Registry.RecordIndex;

const Operation = enum {
    createEnt,
    deleteEnt,
    addComp,
    removeComp,
};

pub fn OperationManager(comptime components: []const Component) type {
    const Storage = ComponentStorage(components);
    const EntityRecord = EntityRecordType(components);
    const HashMap = HashMapType(RecordIndex, EntityRecord);
    
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        entity_records: HashMap = .empty,
        
        operation_queue: OperationQueue = undefined,
        storage: Storage = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            var self: Self = .{
                .allocator = allocator,
                .operation_queue = OperationQueue.init(allocator),
                .storage = Storage.init(allocator),
            };
            
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.operation_queue.deinit();
            self.storage.deinit();
            self.entity_records.deinit(self.allocator);
            self.entity_records.deinit(self.allocator);
        }

        pub fn addOperation(self: *Self, operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
            var ent_record: EntityRecord = .init(record_data);
            
            switch (operation) {
                .addEnt => self.appendAddOperation(&ent_record, component_data),
                .deleteEnt => self.appendRemoveOperation(&ent_record),
                // .addComp => ,
                // .removeComp => ,
            }
        }

        fn appendAddOperation(self: *Self, entity_record: *EntityRecord, component_data: anytype) !void {
            inline for(std.meta.fields(@TypeOf(component_data))) |field| {
                const comp_value = @field(component_data, field_name);
                const comp_array = self.storage.getComponentArray(comp);
                try @field(self.operation_queue, @tagName(Operation.add)).append(self.allocator, comp_value);
            }
            inline for(components) |comp| {
                const field_name = @tagName(comp);
                if(@hasField(@TypeOf(component_data), field_name)) {
                    //@field
                } 
            }
        }
        
        fn appendRemoveOperation(self: *Self ,entity_record: *EntityRecord) void {
            _ = self;
        }

        fn append
    };
}

const InnerOperationQueue = blk: {
    const operations = std.meta.tags(Operation);
    var names: [operations.len][]const u8 = undefined;
    var types: [operations.len]type = undefined;
    var attrs: [operations.len]std.builtin.Type.StructField.Attributes = undefined;

    for (operations, 0..) |operation, i| {
        names[i] = @tagName(operation);
        types[i] = ArrayList(RecordIndex);
        attrs[i] = .{};
    }

    break :blk @Struct(
        .auto,
        null,
        &names,
        &types,
        &attrs,
    );
};

const OperationQueue = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    inner_storage: InnerOperationQueue = undefined,

    pub fn init(allocator: std.mem.Allocator) Self {
        var self: Self = .{ .allocator = allocator };

        inline for (std.meta.fields(InnerOperationQueue)) |field| {
            @field(self.inner_storage, field.name) = .empty;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        inline for (std.meta.fields(InnerOperationQueue)) |field| {
            @field(self.inner_storage, field.name).deinit(self.allocator);
        }
    }

    pub fn getComponentArray(self: *Self, comptime operation: Operation) *ArrayList(RecordIndex) {
        return &@field(self.inner_storage, @tagName(operation));
    }
};
