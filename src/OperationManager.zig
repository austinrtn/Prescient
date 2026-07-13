const std = @import("std");
const MODE = @import("builtin").mode;
const CR = @import("ComponentRegistry.zig").ComponentRegistry;
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Registry = @import("Registry.zig").Registry;
const ComponentStorage = @import("ComponentStorage.zig").ComponentStorage;
const EntityRecordType = @import("EntityRecord.zig").EntityRecord;
const EntityPool = @import("EntPool.zig").EntPool;

const EntityId = Registry.EntityId;
const RecordIndex = Registry.RecordIndex;
const GroupIndex = Registry.GroupIndex;
const OperationIndex = Registry.OperationIndex;
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
    const Self = @This();

    create: bool = false,
    delete: bool = false,
    first_op: ?OperationIndex = null,
    last_op: ?OperationIndex = null,

    /// Sets the last operation to the index argument.
    /// Also sets the first operation if field is null
    fn setNextOp(self: *Self, operation_index: OperationIndex) void {
        if (self.first_op == null) self.first_op = operation_index;
        self.last_op = operation_index;
    }
};

pub fn OperationManager(comptime TAG: PR.Enum) type {
    const Config = PR.GetPoolConfig(TAG);
    const PoolComponent = Config.Component;
    const EntityRecord = EntityRecordType(TAG);
    const RecordData = EntityRecord.RecordData;

    const PendingOperation = struct {
        operation: Operation,
        component: ?PoolComponent,
        component_index: ?ComponentIndex = null,
        next_op: ?OperationIndex = null,
    };

    const PendingEntityData = struct {
        pending_entity: PendingEntity,
        record_data: RecordData,
    };

    const Storage = ComponentStorage(TAG);
    const PendingEntityMap = HashMapType(EntityId, PendingEntityIndex);
    const PendingEntityGroupMap = HashMapType(GroupIndex, ArrayList(PendingEntityData));

    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        entity_pool: *EntityPool(TAG),
        /// Stores an arraylist of Pending Entities as the value, the group / bitmask is the key.
        /// Functionally stores pending entity data, separated by component compisistion
        pending_entity_groups: PendingEntityGroupMap = .empty,

        /// Uses EntityID to lookup PendingEntityData instance that contains both the location of
        /// the pending_entity and record data structs.
        pending_entity_indices: PendingEntityMap = .empty,

        /// A linear arraylist that contains all Pending operations
        pending_operations: ArrayList(PendingOperation) = .empty,

        /// Sparse-set storage that houses all pending component data
        pending_components: Storage = undefined,

        /// Create a new instance of OperationManager
        pub fn init(allocator: std.mem.Allocator, entity_pool: *EntityPool(TAG)) Self {
            return .{
                .allocator = allocator,
                .pending_components = .init(allocator),
                .entity_pool = entity_pool,
            };
        }

        /// Deinitialize OperationManager instance
        pub fn deinit(self: *Self) void {
            for (self.pending_entity_groups.values()) |*list| list.deinit(self.allocator);

            self.pending_entity_groups.deinit(self.allocator);
            self.pending_operations.deinit(self.allocator);
            self.pending_components.deinit();
            self.pending_entity_indices.deinit(self.allocator);
        }

        /// The main control flow for entity-component data being added to the queue.
        pub fn appendOperation(self: *Self, comptime operation: Operation, component_data: anytype, record_data: EntityRecord.RecordData) !void {
            const pending_entity = try self.getOrSetPendingEntityData(record_data, operation);

            switch (operation) {
                .createEnt, .addComp => |op| {
                    // CreateEnt PendingOperations are simple and don't carry component data
                    if (op == .createEnt) {
                        pending_entity.setNextOp(try self.appendNextOperation(
                            .createEnt,
                            null,
                            null,
                            null,
                        ));
                    }

                    // Since appendOperation function calls can still carry data regardless if it is createEnt or addComp
                    // operations, this function is called for both operations
                    try self.appendAddPendingOperation(component_data, pending_entity);
                },
                .removeComp => {
                    try self.appendRemovePendingOperation(component_data, pending_entity);
                },
                .deleteEnt => {
                    pending_entity.setNextOp(try self.appendNextOperation(
                        .deleteEnt,
                        null,
                        null,
                        null,
                    ));
                },
            }
        }

        /// Where compoent and entity data goes when component data is being *added* to the queue.
        /// Loops through each entity field / component, appends each component to the data base,
        /// and records each operation individually.
        fn appendAddPendingOperation(self: *Self, component_data: anytype, pending_entity: *PendingEntity) !void {
            const EntType = @TypeOf(component_data);

            // Each EntType field represents a component that will be queued / flushed.
            inline for (std.meta.fields(EntType)) |field| {
                const comp = comptime Config.getComponentFromName(field.name);
                const comp_val = @field(component_data, field.name);
                const comp_idx = try self.appendPendingComponent(comp, comp_val); // Where pending component data will be stored

                pending_entity.setNextOp(try self.appendNextOperation(
                    .addComp,
                    comp,
                    pending_entity.last_op,
                    comp_idx,
                ));
            }
        }

        fn appendRemovePendingOperation(self: *Self, components: []const PoolComponent, pending_entity: *PendingEntity) !void {
            for (components) |comp| {
                const next_op = try self.appendNextOperation(
                    .removeComp,
                    comp,
                    pending_entity.last_op,
                    null,
                );

                pending_entity.setNextOp(next_op);
            }
        }

        ///Puts or retrives a new GroupHashMap key / value.  Stores group index as key and PendingEntity group [*ArrayList(PendingEntity)] as value
        fn getOrSetPendingEntityGroup(self: *Self, group_index: GroupIndex) !*ArrayList(PendingEntityData) {
            const res = try self.pending_entity_groups.getOrPut(self.allocator, group_index);
            if (!res.found_existing) res.value_ptr.* = .empty;

            return res.value_ptr;
        }

        ///Puts or retrives a new PendingEntity key / value.  Stores HashMap as key and PendingEntity instance as value.
        fn getOrSetPendingEntityData(self: *Self, record_data: RecordData, operation: Operation) !*PendingEntity {
            // If the entity already exists within the operation manager...

            if (self.pending_entity_indices.get(record_data.entity_id)) |pend_ent_idx| {

                // Get the group arraylist that the PendingEntity data should exist within
                const group = self.pending_entity_groups.getPtr(record_data.group_index).?;
                const pend_ent_data = &group.items[pend_ent_idx.idx()];
                const pend_ent = &pend_ent_data.pending_entity;

                std.debug.assert(pend_ent_idx.idx() < group.items.len);
                std.debug.assert(std.meta.eql(pend_ent_data.record_data, record_data));

                pend_ent.create = (pend_ent.create or operation == .createEnt);
                pend_ent.delete = (pend_ent.delete or operation == .deleteEnt);
                return pend_ent;
            }
            // If the entity does not yet exist within the operation manager
            // Create a new PendingEntity instance as well as PendingEntityIndex
            // and add it to the operation manager
            const group = try self.getOrSetPendingEntityGroup(record_data.group_index);
            const pend_ent_idx: PendingEntityIndex = .init(group.items.len);
            const pend_ent: PendingEntity = .{
                .create = (operation == .createEnt),
                .delete = (operation == .deleteEnt),
            };

            try group.append(self.allocator, .{ .pending_entity = pend_ent, .record_data = record_data });
            errdefer _ = group.pop();

            try self.pending_entity_indices.put(
                self.allocator,
                record_data.entity_id,
                pend_ent_idx,
            );

            return &group.items[pend_ent_idx.idx()].pending_entity;
        }

        /// Add component data to the OperationManager, pending for flush
        fn appendPendingComponent(self: *Self, comptime component: PoolComponent, component_value: anytype) !ComponentIndex {
            // Convert anomous struct data into typed data
            const converted_comp = CR.convertAnomToComponent(component_value, @tagName(component));
            const component_index: ComponentIndex = .init(self.pending_components.getComponentArrayLen(component));

            try self.pending_components.append(component, converted_comp);

            return component_index;
        }

        /// Creates a new PendingOperation instance and appends it to the pending_operations arraylist.
        fn appendNextOperation(self: *Self, comptime operation: Operation, component: ?PoolComponent, previous_operation_index: ?OperationIndex, component_index: ?ComponentIndex) !OperationIndex {
            const pend_op_idx = self.pending_operations.items.len;

            const pend_op: PendingOperation = .{
                .operation = operation,
                .component = component,
                .component_index = component_index,
                .next_op = null,
            };

            try self.pending_operations.append(self.allocator, pend_op);

            // If a previous operation for that entity exists, update it's next_op field to maintain a linked-list
            if (previous_operation_index) |prev_idx| self.pending_operations.items[prev_idx.idx()].next_op = .init(pend_op_idx);

            return .init(pend_op_idx);
        }

        pub fn flush(self: *Self) !void {
            const ArchPool = @import("ArchetypePool.zig").ArchetypePool(TAG);
            const allocator = testing.allocator;

            var pool: ArchPool = .init(allocator);
            _ = &pool;

            for (self.pending_entity_groups.values()) |group| {
                for (group.items) |pend_ent_data| {
                    const pend_ent = &pend_ent_data.pending_entity;
                    const record_data = pend_ent_data.record_data;

                    var next_op_idx = pend_ent.first_op orelse continue;
                    var ent_record: EntityRecord = .init(record_data);
                    
                    while (true) {
                        const next_op = self.pending_operations.items[next_op_idx.idx()];

                        if (next_op.component) |component| switch (component) {
                            inline else => |comp| {
                                switch (next_op.operation) {
                                    .addComp => ent_record.setComponentIndex(comp, next_op.component_index.?),
                                    else => {},
                                }
                            },
                        };

                        next_op_idx = next_op.next_op orelse break;
                    }

                    var iter = ent_record.iter();
                    while(iter.next()) |comp| std.debug.print("{s}\n", .{@tagName(comp)});
                }
            }
        }
    };
}

///Begining to wonder if EntityRecords are uncessary at this point... makes sense when one ent can own one component,
/// but with this operation queue, many ents can have many of the same components.  And their location is already being handled in a linked list
/// Could be useful for "collapsing" the operations.
///
/// Next step is omitting the EntityRecords list and creating a flush mechanism.  The first focus will just be to just resolve entity operations
const testing = std.testing;
test "Start" {
    const tag = PR.Tags[0];
    const Config = PR.GetPoolConfig(tag);
    const ArchPool = @import("ArchetypePool.zig").ArchetypePool(tag);
    const allocator = testing.allocator;

    var pool: ArchPool = .init(allocator);
    defer pool.deinit();

    var op_manager: OperationManager(tag) = .init(allocator, &pool);
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

    try op_manager.appendOperation(.addComp, .{
        .foo = 12,
    }, record_data);
    try op_manager.appendOperation(.removeComp, &.{ .foo, .id }, record_data);
    try op_manager.appendOperation(.deleteEnt, null, record_data);

    try testing.expectEqual(@as(usize, 2), op_manager.pending_entity_groups.count());
    try testing.expectEqual(@as(usize, 2), op_manager.pending_entity_indices.count());
    try testing.expectEqual(@as(usize, 0), op_manager.pending_entity_indices.get(.init(0)).?.idx());
    try testing.expectEqual(@as(usize, 0), op_manager.pending_entity_indices.get(.init(1)).?.idx());

    try op_manager.flush();

    std.debug.print(
        \\
        \\Pending entities
        \\+-------+-------+--------+--------+--------+--------+----------+---------+
        \\| group | index | entity | record | create | delete | first op | last op |
        \\+-------+-------+--------+--------+--------+--------+----------+---------+
        \\
    , .{});
    for (op_manager.pending_entity_groups.keys(), op_manager.pending_entity_groups.values()) |group_index, pending_entities| {
        for (pending_entities.items, 0..) |pending_entity_data, pending_entity_index| {
            const pending_entity = pending_entity_data.pending_entity;
            const record_data_stored = pending_entity_data.record_data;

            std.debug.print(
                "|{d: >6} |{d: >6} | {any: >6} | {any: >6} | ",
                .{
                    group_index.val,
                    pending_entity_index,
                    record_data_stored.entity_id.val,
                    record_data_stored.record_index.val,
                },
            );
            std.debug.print("{any: >6} | {any: >6} | ", .{
                pending_entity.create,
                pending_entity.delete,
            });
            if (pending_entity.first_op) |first_op| {
                std.debug.print("{d: >8}", .{first_op.val});
            } else {
                std.debug.print("{s: >8}", .{"-"});
            }
            std.debug.print(" | ", .{});
            if (pending_entity.last_op) |last_op| {
                std.debug.print("{d: >7}", .{last_op.val});
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
        const component_name = if (pending_operation.component) |component|
            @tagName(component)
        else
            "-";
        std.debug.print(
            "| {d: >5} | {s: <10} | {s: <9} | ",
            .{
                operation_index,
                @tagName(pending_operation.operation),
                component_name,
            },
        );
        if (pending_operation.component_index) |component_index| {
            std.debug.print("{d: >15}", .{component_index.val});
        } else {
            std.debug.print("{s: >15}", .{"-"});
        }
        std.debug.print(" | ", .{});
        if (pending_operation.next_op) |next_op| {
            std.debug.print("{d: >7}", .{next_op.val});
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
