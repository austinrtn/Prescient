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

const PendingEntity = struct {
    create: bool = false,
    delete: bool = false,
    
    first_op: ?u32 = null,
    last_op: ?u32 = null,
    
    record_index: RecordIndex,
};

const PendingOperation = struct {
    operation: enum{add, remove},
    component_index: ComponentIndex, 
    
    next_op: ?u32 = null,
};

pub fn OperationManager(comptime PoolComponent: type) type {
    const Storage = ComponentStorage(PoolComponent);
    const EntityRecord = EntityRecordType(PoolComponent.Enum);
    const RecordData = EntityRecord.RecordData;
    const HashMap = HashMapType(EntityId, PendingEntity);
    
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,

        entity_records: ArrayList(EntityRecord) = .empty,
        groups: ArrayList(EntityId) = .empty,
        
        pending_entities: HashMap = .empty,
        pending_operations: ArrayList(PendingOperation) = .empty,
        pending_components: Storage = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .pending_components = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.groups.deinit(self.allocator);
            self.pending_operations.deinit(self.allocator);
            self.pending_components.deinit();
            self.entity_records.deinit(self.allocator);
            self.pending_entities.deinit(self.allocator);
        }

        pub fn appendOperation(self: *Self, comptime operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
            const pend_ent = try self.getOrSetPendingEntity(record_data, operation);
            
            switch (operation) {
                .createEnt => {
                    // pending_op = try self.appendCreateEnt(component_data, &ent_record);
                },
                
                .addComp, .removeComp => |op| {
                    
                },
                
                .deleteEnt => {
                    
                },
            }
            
            try operations.append(self.allocator, pending_op);
            try self.entity_records.append(self.allocator, ent_record);
        }

        fn getOrSetPendingEntity(self: *Self, record_data: RecordData, operation: Operation) !*PendingEntity {
            const res = try self.pending_entities.getOrPut(self.allocator, record_data.entity_id);
            if(!res.found_existing) res.value_ptr.* = .{
                .create = (operation == .createEnt), 
                .delete = (operation == .deleteEnt),
                .record_index = self.entity_records.items.len,
            };

            try self.entity_records.append(self.allocator, .init(record_data));
            return res.value_ptr;
        }

        fn getEntitysLastOperation(self: *Self, pending_entity: PendingEntity) ?PendingOperation {
            if(pending_entity.last) |last| return self.pending_operations.items[@intCast(last)]
            else return null;
        }

        fn addComponentToPending(self: *Self, comptime compoennt: PoolComponent.Enum, comp_value: CR.GetComponentTypeByEnum(PoolCompoent.Globalize))
        
        fn appendCreateEnt(self: *Self, component_data: anytype, entity_record: *EntityRecord) !PendingOperation {
            const EntType = @TypeOf(component_data);
            
            inline for(PoolComponent.Tags) |comp| {
                const field_name = @tagName(comp);
                if(@hasField(EntType, field_name)) {
                    const comp_value = blk: {
                        const val = @field(component_data, field_name);
                        break :blk CR.convertAnomToComponent(val, field_name);
                    };
                    
                    const comp_list = self.pending_components.getComponentArray(comp);
                    const comp_idx = comp_list.items.len;
    
                    try comp_list.append(self.allocator, comp_value);
                    entity_record.setComponentIndex(comp, comp_idx);

                    pending_op.component_indicies[pending_op.count] = entity_record.getComponentIndex(comp).?;
                    pending_op.count += 1;
                }
            }
            
            return pending_op;
        }

        // pub fn appendAddComponent(self: *Self, component_value: )
    };
}

const testing = std.testing;

test "Start" {
    const PR = @import("PoolRegistry.zig").PoolRegistry;
    const ComponentSubset = @import("ComponentSubset.zig").ComponentSubset;
    const tag = PR.Tags[0];
    const Comps = ComponentSubset(tag);
    
    var op_manager: OperationManager(Comps) = .init(testing.allocator);
    defer op_manager.deinit();

    const ent = .{
        .pos = .{.x = 0, .y = 0},
    };

    const record_data: EntityRecordType(Comps).RecordData = .{
        .entity_id = .init(0),
        .group_index = .init(0),
        .member_index = .init(0),
        .record_index = .init(0),
    };

    try op_manager.appendOperation(.createEnt, ent, record_data);

    for(op_manager.pending_entities.keys(), 0..) |ent_id, i| {
        std.debug.print("{}:\n", .{ent_id.val});
        const operation_list = op_manager.pending_entities.values()[i];

        try testing.expect(operation_list.items.len == 1);
        for(operation_list.items) |op| {
            std.debug.print(">> {any}\n", .{op});
        }

        std.debug.print("\n", .{});
    }
}