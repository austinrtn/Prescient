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
const PendingEntityIndex = Registry.PendingEntityIndex;

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
    const PendingEntityIndexMap = HashMapType(EntityId, PendingEntityIndex);
    const PendingEntityGroupMap = HashMapType(GroupIndex, ArrayList(PendingEntity));

    const PendingOperation = struct {
        operation: Operation,
        component: PoolComponent,
        component_index: ?ComponentIndex = null,
        next_op: ?u32 = null,
    };

    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,

        entity_records: ArrayList(EntityRecord) = .empty, //Used to store entity records of each ent.  Don't think is necessary but keeping for now  
        pending_entity_groups: PendingEntityGroupMap = .empty, //Stores an arraylist of Pending Entities as the value, the group / bitmask is the key.  
                                                                // Functionally stores pending entity data partioned by component compisistion

        pending_entity_indices: PendingEntityIndexMap = .empty, // Stores an index to where the the PendingEntity struct exist within pending_entity_groups group list.  
                                                                // Requires record data / group index to look up which group list it exist within
                                                                
        pending_operations: ArrayList(PendingOperation) = .empty, // A linear arraylist that contains all Pending operations
        pending_components: Storage = undefined, // Sparse-set storage that houses all pending component data 

        /// Create a new instance of OperationManager
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .pending_components = .init(allocator),
            };
        }

        /// Deinitialize OperationManager instance
        pub fn deinit(self: *Self) void {
            for (self.pending_entity_groups.values()) |*list| list.deinit(self.allocator);

            self.pending_entity_groups.deinit(self.allocator);
            self.pending_operations.deinit(self.allocator);
            self.pending_components.deinit();
            self.entity_records.deinit(self.allocator);
            self.pending_entity_indices.deinit(self.allocator);
        }

        /// The main control flow for entity-component data being added to the queue.  
        pub fn appendOperation(self: *Self, comptime operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
            const pending_entity = try self.getOrSetPendingEntity(record_data, operation);
            const entity_record = &self.entity_records.items[pending_entity.record_index.idx()];  

            switch (operation) {
                .createEnt, .addComp => {
                    try self.appendAddPendingOperation(operation, component_data, pending_entity, entity_record);
                },
                else => {},
            }
            //     .removeComp => {

            //     },
            //     .deleteEnt => {

            //     },
            // }
        }

        /// Where compoent and entity data goes when component data is being *added* to the queue.  
        /// Goes through each entity field / component, appends each component to the data base, 
        /// and records each operation individually.
        fn appendAddPendingOperation(self: *Self, comptime operation: Operation, component_data: anytype, pending_entity: *PendingEntity, entity_record: *EntityRecord) !void {
            const EntType = @TypeOf(component_data);
            // Get last operation and check to see if this is the entity's first operation in this manager state
            var last_operation_index = pending_entity.last_op;
            var ents_first_op = (pending_entity.first_op == null);
            
            // Each EntType field represents a component that will be queued / flushed.  
            inline for(std.meta.fields(EntType)) |field| {
                const comp = comptime Config.getComponentFromName(field.name);
                const comp_val = @field(component_data, field.name);
                const comp_idx = try self.appendPendingComponent(comp, comp_val); // Where pending component data will be stored

                const operation_index = try self.appendNextOperation(
                    operation,
                    comp,
                    last_operation_index,
                    comp_idx,
                );
                
                pending_entity.last_op = operation_index; // Track Pending Entity's last operation
                last_operation_index = operation_index;
                entity_record.setComponentIndex(comp, comp_idx);

                if (ents_first_op) {
                    pending_entity.first_op = operation_index;
                    ents_first_op = false;
                }
            }
        }

        ///Puts or retrives a new GroupHashMap key / value 
        fn getOrSetPendingEntityGroup(self: *Self, group_index: GroupIndex) !*ArrayList(PendingEntity) {
            const result = try self.pending_entity_groups.getOrPut(self.allocator, group_index);
            if (!result.found_existing) result.value_ptr.* = .empty;

            return result.value_ptr;
        }

        fn getOrSetPendingEntity(self: *Self, record_data: RecordData, operation: Operation) !*PendingEntity {
            if (self.pending_entity_indices.get(record_data.entity_id)) |pending_entity_index| {
                const group = self.pending_entity_groups.getPtr(record_data.group_index).?;
                std.debug.assert(pending_entity_index.idx() < group.items.len);

                const pending_entity = &group.items[pending_entity_index.idx()];
                const entity_record = self.entity_records.items[pending_entity.record_index.idx()];
                std.debug.assert(entity_record.entity_id.eql(record_data.entity_id));

                pending_entity.create = (pending_entity.create or operation == .createEnt);
                pending_entity.delete = (pending_entity.delete or operation == .deleteEnt);
                return pending_entity;
            }

            const group = try self.getOrSetPendingEntityGroup(record_data.group_index);
            const pending_entity_index: PendingEntityIndex = .init(group.items.len);
            const pending_entity: PendingEntity = .{
                .create = (operation == .createEnt),
                .delete = (operation == .deleteEnt),
                .record_index = .init(self.entity_records.items.len),
            };

            try self.entity_records.append(self.allocator, .init(record_data));
            errdefer _ = self.entity_records.pop();

            try group.append(self.allocator, pending_entity);
            errdefer _ = group.pop();

            try self.pending_entity_indices.put(
                self.allocator,
                record_data.entity_id,
                pending_entity_index,
            );

            return &group.items[pending_entity_index.idx()];
        }

        fn appendPendingComponent(self: *Self, comptime component: PoolComponent, component_value: anytype) !ComponentIndex {
            const converted_comp = CR.convertAnomToComponent(component_value, @tagName(component));
            const component_index: ComponentIndex = .init(self.pending_components.getComponentArrayLen(component));

            try self.pending_components.append(component, converted_comp);

            return component_index;
        }

        fn appendNextOperation(self: *Self, comptime operation: Operation, comptime component: PoolComponent, previous_operation_index: ?u32, component_index: ?ComponentIndex) !u32 {
            const pend_op_idx = self.pending_operations.items.len;

            const pend_op: PendingOperation = .{
                .operation = operation,
                .component = component,
                .component_index = component_index,
                .next_op = null,
            };

            try self.pending_operations.append(self.allocator, pend_op);
            if (previous_operation_index) |previous_index| {
                self.pending_operations.items[previous_index].next_op = @intCast(pend_op_idx);
            }

            return @intCast(pend_op_idx);
        }
    };
}

///Begining to wonder if EntityRecords are uncessary at this point... makes sense when one ent can own one component, 
/// but with this operation queue, many ents can have many of the same components.  And their location is already being handled in a linked list
/// Could be useful for "collapsing" the operations.

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
    record_data.group_index.val = 1;
    try op_manager.appendOperation(.createEnt, ent, record_data);

    try op_manager.appendOperation(.addComp, .{.foo = 12,}, record_data);

    try testing.expectEqual(@as(usize, 2), op_manager.pending_entity_groups.count());
    try testing.expectEqual(@as(usize, 2), op_manager.pending_entity_indices.count());
    try testing.expectEqual(@as(usize, 0), op_manager.pending_entity_indices.get(.init(0)).?.idx());
    try testing.expectEqual(@as(usize, 0), op_manager.pending_entity_indices.get(.init(1)).?.idx());

    std.debug.print(
        \\
        \\Pending entities
        \\+-------+-------+--------+--------+--------+--------+----------+---------+
        \\| group | index | entity | record | create | delete | first op | last op |
        \\+-------+-------+--------+--------+--------+--------+----------+---------+
        \\
    , .{});
    for (op_manager.pending_entity_groups.keys(), op_manager.pending_entity_groups.values()) |group_index, pending_entities| {
        for (pending_entities.items, 0..) |pending_entity, pending_entity_index| {
            const entity_id = op_manager.entity_records.items[pending_entity.record_index.idx()].entity_id;
            std.debug.print(
                "| {d: >5} | {d: >5} | {d: >6} | {d: >6} | {any: >6} | {any: >6} | ",
                .{
                    group_index.val,
                    pending_entity_index,
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
    }
    std.debug.print(
        \\+-------+-------+--------+--------+--------+--------+----------+---------+
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
