const std = @import("std");
const MODE = @import("builtin").mode;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const Registry = @import("Registry.zig").Registry;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;
const EntityRecordType = @import("EntityRecord.zig").EntityRecord;

const ArrayList = std.ArrayList;
const HashMapType = std.AutoArrayHashMapUnmanaged;
const EntityId = Registry.EntityId;
const ComponentIndex = Registry.ComponentIndex;
const Component = CR.Enum;
const RecordIndex = Registry.RecordIndex;

const Operation = enum {
    addEnt,
    deleteEnt,
    addComp,
    removeComp,
};

const PendingOperation = struct {
    operation: Operation,
    record_index: RecordIndex,
    src_bitmask: CR.BitSet,
    dest_bitmask: CR.BitSet,
};

pub fn OperationManager(comptime components: []const Component) type {
    const Storage = ComponentStorage(components);
    const EntityRecord = EntityRecordType(components);
    const HashMap = HashMapType(EntityId, ArrayList(PendingOperation));

    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        
        entity_records: ArrayList(EntityRecord) = .empty,
        pending_operations: HashMap = .empty,
        
        storage: Storage = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .storage = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.storage.deinit();
            self.entity_records.deinit(self.allocator);
            for(self.pending_operations.values()) |*list| list.deinit(self.allocator);
            self.pending_operations.deinit(self.allocator);
        }

        pub fn addOperation(self: *Self, comptime operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
            const ent_id = record_data.entity_id;
            var ent_record: EntityRecord = .init(record_data);

            // If not adding an ent for creation,
            if (comptime operation != .addEnt) {
                const res = try self.entity_records.getOrPut(self.allocator, record_data.entity_id);
                if (res.found_existing) ent_record = res.value_ptr.entity_record;
            }

            switch (operation) {
                .addEnt => {
                    if (comptime MODE == .Debug or MODE == .ReleaseSafe) {
                        const found_ent = self.entity_records.get(record_data.entity_id);
                        if (operation == .addEnt and found_ent != null) {
                            std.debug.panic("Duplicate create entity operation found for EntityId {}\n", .{ent_id});
                        }
                    }

                    self.appendAddOperation(.addEnt, &ent_record, component_data);
                    const record_operation: RecordOperation = .{ .entity_record = record_data.entity_id, .operation = operation };
                    try self.entity_records.putNoClobber(self.allocator, ent_id, record_operation);
                },
                .addComp => {
                    self.appendAddOperation(.addEnt, &ent_record, component_data);
                    const record_operation: RecordOperation = .{ .entity_record = record_data.entity_id, .operation = operation };
                    try self.entity_records.put(self.allocator, ent_id, record_operation);
                },
                // .deleteEnt => self.appendRemoveOperation(&ent_record),
                // // .removeComp => ,
            }
        }

        fn appendAddOperation(self: *Self, comptime operation: Operation, entity_record: *EntityRecord, component_data: anytype) !void {
            if (operation != .addEnt or operation != .addComp)
                @compileError("Invalid Operation value for appendAddOperation function");

            inline for (std.meta.fields(@TypeOf(component_data))) |field| {
                const comp_tag = comptime CR.getEnumByName(field.name);
                const comp_value = @field(component_data, field.name);
                const comp_list = self.storage.getComponentArray(comp_tag);
                try comp_list.append(self.allocator, comp_value);
                entity_record.setComponentIndex(comp_tag, comp_list.items.len - 1);
            }
        }

        fn appendRemoveOperation(self: *Self, entity_record: *EntityRecord) void {
            _ = self;
            _ = entity_record;
        }
    };
}

// const InnerOperationQueue = blk: {
//     const operations = std.meta.tags(Operation);
//     var names: [operations.len][]const u8 = undefined;
//     var types: [operations.len]type = undefined;
//     var attrs: [operations.len]std.builtin.Type.StructField.Attributes = undefined;

//     for (operations, 0..) |operation, i| {
//         names[i] = @tagName(operation);
//         types[i] = ArrayList(RecordIndex);
//         attrs[i] = .{};
//     }

//     break :blk @Struct(
//         .auto,
//         null,
//         &names,
//         &types,
//         &attrs,
//     );
// };

// const OperationQueue = struct {
//     const Self = @This();

//     allocator: std.mem.Allocator,
//     inner_storage: InnerOperationQueue = undefined,

//     pub fn init(allocator: std.mem.Allocator) Self {
//         var self: Self = .{ .allocator = allocator };

//         inline for (std.meta.fields(InnerOperationQueue)) |field| {
//             @field(self.inner_storage, field.name) = .empty;
//         }

//         return self;
//     }

//     pub fn deinit(self: *Self) void {
//         inline for (std.meta.fields(InnerOperationQueue)) |field| {
//             @field(self.inner_storage, field.name).deinit(self.allocator);
//         }
//     }

//     pub fn addToOperationArray(self: *Self, comptime operation: Operation, record_index: RecordIndex) !void {
//         const op_array = self.getOperationArray(operation);
//         try op_array.append(self.allocator, record_index);
//     }

//     pub fn getOperationArray(self: *Self, comptime operation: Operation) *ArrayList(RecordIndex) {
//         return &@field(self.inner_storage, @tagName(operation));
//     }
// };
