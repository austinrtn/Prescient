const std = @import("std");
const MODE = @import("builtin").mode;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Registry = @import("Registry.zig").Registry;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;
const EntityRecordType = @import("EntityRecord.zig").EntityRecord;

const EntityId = Registry.EntityId;
const RecordIndex = Registry.RecordIndex;
const GroupIndex = Registry.GroupIndex;
const OperationIndex = Registry.OperationIndex;

const ArrayList = std.ArrayList;
const HashMapType = std.AutoArrayHashMapUnmanaged;
const ComponentIndex = Registry.ComponentIndex;
const Component = CR.Component;

const Operation = enum(u8) {
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

pub fn OperationManager(comptime TAG: PR.Enum) type {
    const Config = PR.GetPoolConfig(TAG);
    const PoolComponent = Config.Component;
    //const Global = Config.globalize;

    const Storage = ComponentStorage(TAG);
    const EntityRecord = EntityRecordType(TAG);
    const RecordData = EntityRecord.RecordData;
    const PendEntHashMap = HashMapType(EntityId, PendingEntity);
    const GroupHashMap = HashMapType(GroupIndex, ArrayList(PendingEntity));

    const PendingOperation = struct {
        operation: Operation,
        component: PoolComponent,
        component_index: ?ComponentIndex = null,
        next_op: ?u32 = null,
    };

    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,

        entity_records: ArrayList(EntityRecord) = .empty,
        groups: GroupHashMap = .empty,

        pending_entities: PendEntHashMap = .empty,
        pending_operations: ArrayList(PendingOperation) = .empty,
        pending_components: Storage = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .pending_components = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for(self.groups.values()) |*list| list.deinit(self.allocator);
                
            self.groups.deinit(self.allocator);
            self.pending_operations.deinit(self.allocator);
            self.pending_components.deinit();
            self.entity_records.deinit(self.allocator);
            self.pending_entities.deinit(self.allocator);
        }

        pub fn appendOperation(self: *Self, comptime operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
            const pend_ent = try self.getOrSetPendingEntity(record_data, operation);
            const ent_record = &self.entity_records.items[pend_ent.record_index.idx()];

            switch (operation) {
                .createEnt, .addComp => |op| {
                    _ = op;
                    try self.appendAddPendingOperation(operation, component_data, pend_ent, ent_record);
                },
                else => {},
            }
            //     .removeComp => {

            //     },
            //     .deleteEnt => {

            //     },
            // }
        }

        fn appendAddPendingOperation(self: *Self, comptime operation: Operation, component_data: anytype, pending_entity: *PendingEntity, entity_record: *EntityRecord) !void {
            const EntType = @TypeOf(component_data);
            var last_op = self.getEntitysLastOperation(pending_entity.*);
            var ents_first_op = (pending_entity.first_op == null);

            inline for (Config.ComponentTags) |comp| {
                const field_name = @tagName(comp);
                if (@hasField(EntType, field_name)) {
                    const comp_val = @field(component_data, field_name);
                    const comp_idx = try self.appendPendingComponent(comp, comp_val);

                    const last_op_idx = try self.appendNextOperation(operation, comp, last_op, comp_idx);
                    pending_entity.last_op = last_op_idx;

                    last_op = &self.pending_operations.items[last_op_idx];
                    entity_record.setComponentIndex(comp, comp_idx);

                    if (ents_first_op) {
                        pending_entity.first_op = last_op_idx;
                        ents_first_op = false;
                    }
                }
            }
        }

        fn getOrSetPendingEntity(self: *Self, record_data: RecordData, operation: Operation) !*PendingEntity {
            const res = try self.pending_entities.getOrPut(self.allocator, record_data.entity_id);
            if (!res.found_existing) {
                res.value_ptr.* = .{
                    .create = (operation == .createEnt),
                    .delete = (operation == .deleteEnt),
                    .record_index = .init(self.entity_records.items.len),
                };

                try self.entity_records.append(self.allocator, .init(record_data));
               
               // Ok I think that instead of self.pending_ents having value of PendingEnt, it should be a new 'OperationIndex' typed
               // index that points to where in the group the pending entity data exist.  Or I could probably use MemberIndex, but I 
               // think I'll try to keep the types distinct 
                const group_list = try self.getOrSetGroup(res.pt);
                try group_list.append(self.allocator, record_data.entity_id);
            }
            return res.value_ptr;
        }

        fn getEntitysLastOperation(self: *Self, pending_entity: PendingEntity) ?*PendingOperation {
            if (pending_entity.last_op) |last| return &self.pending_operations.items[@intCast(last)] else return null;
        }

        fn appendPendingComponent(self: *Self, comptime component: PoolComponent, component_value: anytype) !ComponentIndex {
            const converted_comp = CR.convertAnomToComponent(component_value, @tagName(component));

            try self.pending_components.append(component, converted_comp);

            return .init(self.pending_components.getComponentArrayLen(component));
        }

        fn appendNextOperation(self: *Self, comptime operation: Operation, comptime component: PoolComponent, last_operation: ?*PendingOperation, componet_index: ?ComponentIndex) !u32 {
            const pend_op_idx = self.pending_operations.items.len;

            const pend_op: PendingOperation = .{
                .operation = operation,
                .component = component,
                .component_index = componet_index,
                .next_op = null,
            };

            try self.pending_operations.append(self.allocator, pend_op);
            if (last_operation) |*last| {
                last.*.next_op = @intCast(pend_op_idx);
            }

            return @intCast(pend_op_idx);
        }

        fn getOrSetGroup(self: *Self, group: GroupIndex) !*ArrayList(EntityId) {
            const res = try self.groups.getOrPut(self.allocator, group);
            if(!res.found_existing) res.value_ptr.* = .empty;
            
            return res.value_ptr;
        }
    };
}

const testing = std.testing;

test "Start" {
    const tag = PR.Tags[0];
    const Config = PR.GetPoolConfig(tag);

    var op_manager: OperationManager(tag) = .init(testing.allocator);
    defer op_manager.deinit();

    const ent = .{
        .pos = .{ .x = 0, .y = 0 },
        .vel = .{ .xvel = 1, .yvel = 3 },
        .id = 69,
    };

    var record_data: EntityRecordType(tag).RecordData = .{
        .entity_id = .init(0),
        .group_index = .init(0),
        .member_index = .init(0),
        .record_index = .init(0),
    };

    try op_manager.appendOperation(.createEnt, ent, record_data);
    record_data.entity_id.val = 1;
    try op_manager.appendOperation(.createEnt, ent, record_data);

    std.debug.print(
        \\
        \\Pending entities
        \\+--------+--------+--------+--------+----------+---------+
        \\| entity | record | create | delete | first op | last op |
        \\+--------+--------+--------+--------+----------+---------+
        \\
    , .{});
    for (op_manager.pending_entities.keys(), op_manager.pending_entities.values()) |entity_id, pending_entity| {
        std.debug.print(
            "| {d: >6} | {d: >6} | {any: >6} | {any: >6} | ",
            .{
                entity_id.val,
                pending_entity.record_index.val,
                pending_entity.create,
                pending_entity.delete,
            },
        );
        if (pending_entity.first_op) |first_op| {
            std.debug.print("{d: >8}", .{first_op});
        } else {
            std.debug.print("{s: >8}", .{"-"});
        }
        std.debug.print(" | ", .{});
        if (pending_entity.last_op) |last_op| {
            std.debug.print("{d: >7}", .{last_op});
        } else {
            std.debug.print("{s: >7}", .{"-"});
        }
        std.debug.print(" |\n", .{});
    }
    std.debug.print(
        \\+--------+--------+--------+--------+----------+---------+
        \\
        \\Pending operations
        \\+-------+------------+-----------+-----------------+---------+
        \\| index | operation  | component | component index | next op |
        \\+-------+------------+-----------+-----------------+---------+
        \\
    , .{});
    for (op_manager.pending_operations.items, 0..) |pending_operation, operation_index| {
        std.debug.print(
            "| {d: >5} | {s: <10} | {s: <9} | ",
            .{
                operation_index,
                @tagName(pending_operation.operation),
                @tagName(pending_operation.component),
            },
        );
        if (pending_operation.component_index) |component_index| {
            std.debug.print("{d: >15}", .{component_index.val});
        } else {
            std.debug.print("{s: >15}", .{"-"});
        }
        std.debug.print(" | ", .{});
        if (pending_operation.next_op) |next_op| {
            std.debug.print("{d: >7}", .{next_op});
        } else {
            std.debug.print("{s: >7}", .{"-"});
        }
        std.debug.print(" |\n", .{});
    }
    std.debug.print(
        \\+-------+------------+-----------+-----------------+---------+
        \\
        \\Pending components
        \\+-----------+-------+------------------------------+
        \\| component | index | value                        |
        \\+-----------+-------+------------------------------+
        \\
    , .{});
    inline for (Config.ComponentTags) |component| {
        const component_items = op_manager.pending_components.getComponentArray(component).items;
        for (component_items, 0..) |component_value, component_index| {
            std.debug.print(
                "| {s: <9} | {d: >5} | {any} |\n",
                .{ @tagName(component), component_index, component_value },
            );
        }
    }
    std.debug.print("+-----------+-------+------------------------------+\n", .{});
}
