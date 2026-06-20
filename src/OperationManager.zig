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
    createEnt,
    deleteEnt,
    addComp,
    removeComp,
};

const PendingOperation = struct {
    operation: Operation,
    component: ?Component = null,
    component_index: ?ComponentIndex = null,
};

pub fn OperationManager(comptime PoolComponent: type) type {
    const Storage = ComponentStorage(PoolComponent);
    const EntityRecord = EntityRecordType(PoolComponent.Enum);
    const HashMap = HashMapType(EntityId, ArrayList(PendingOperation));

    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,

        entity_records: ArrayList(EntityRecord) = .empty,
        pending_operations: HashMap = .empty,
        pending_components: Storage = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .pending_components = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.pending_components.deinit();
            self.entity_records.deinit(self.allocator);
            for (self.pending_operations.values()) |*list| list.deinit(self.allocator);
            self.pending_operations.deinit(self.allocator);
        }

        pub fn appendOperation(self: *Self, comptime operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
            const ent_id = record_data.entity_id;
            const ent_record = EntityRecord.init(record_data);

            const operations = blk: {
                const res = try self.pending_operations.getOrPut(self.allocator, ent_id);
                if(!res.found_existing) {
                    res.value_ptr.* = .empty;
                }
                break :blk res.value_ptr;
            };
            
            switch (operation) {
                .createEnt => {
                    
                },
                
                .addComp => {
                    
                },
                
                .deleteEnt => {
                    
                },
                
                .removeComp => {
                    
                },
            }
            
            try self.entity_records.append(ent_record);
        }

        pub fn appendCreateEnt(self: *Self, component_data: anytype) !void {
            
        }
        
        // pub fn addOperation(self: *Self, comptime operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
        //     const ent_id = record_data.entity_id;
        //     var ent_record: EntityRecord = .init(record_data);

        //     // If not adding an ent for creation,
        //     if (comptime operation != .addEnt) {
        //         const res = try self.entity_records.getOrPut(self.allocator, record_data.entity_id);
        //         if (res.found_existing) ent_record = res.value_ptr.entity_record;
        //     }

        //     switch (operation) {
        //         .addEnt => {
        //             if (comptime MODE == .Debug or MODE == .ReleaseSafe) {
        //                 const found_ent = self.entity_records.get(record_data.entity_id);
        //                 if (operation == .addEnt and found_ent != null) {
        //                     std.debug.panic("Duplicate create entity operation found for EntityId {}\n", .{ent_id});
        //                 }
        //             }

        //             self.appendAddOperation(.addEnt, &ent_record, component_data);
        //             const record_operation: RecordOperation = .{ .entity_record = record_data.entity_id, .operation = operation };
        //             try self.entity_records.putNoClobber(self.allocator, ent_id, record_operation);
        //         },
        //         .addComp => {
        //             self.appendAddOperation(.addEnt, &ent_record, component_data);
        //             const record_operation: RecordOperation = .{ .entity_record = record_data.entity_id, .operation = operation };
        //             try self.entity_records.put(self.allocator, ent_id, record_operation);
        //         },
        //         // .deleteEnt => self.appendRemoveOperation(&ent_record),
        //         // // .removeComp => ,
        //     }
        // }

        fn appendAddOperation(self: *Self, comptime operation: Operation, entity_record: *EntityRecord, component_data: anytype) !void {
            if (operation != .addEnt or operation != .addComp)
                @compileError("Invalid Operation value for appendAddOperation function");

            inline for (std.meta.fields(@TypeOf(component_data))) |field| {
                const comp_tag = comptime PoolComponent.localize(CR.getEnumByName(field.name));
                const comp_value = @field(component_data, field.name);
                const comp_list = self.pending_components.getComponentArray(comp_tag);
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

const testing = std.testing;

test "Start" {
}