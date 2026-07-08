const std = @import("std");
const PR = @import("PoolRegistry.zig").PoolRegistry;
const Registry = @import("Registry.zig").Registry;
const EntityId = Registry.EntityId;
const GroupIndex = Registry.GroupIndex;
const MemberIndex = Registry.MemberIndex;
const RecordIndex = Registry.RecordIndex;
const ComponentIndex = Registry.ComponentIndex;

pub fn EntityRecord(comptime TAG: PR.Enum) type {
    const Config = PR.GetPoolConfig(TAG);
    const PoolComponent = Config.Component;
    const InnerEntRecord = InnerEntityRecord(TAG);
    return struct {
        pub const RecordData = struct {
            entity_id: EntityId,
            group_index: GroupIndex,
            member_index: MemberIndex,
            record_index: RecordIndex,
        };

        pub const Self = @This();
        allocator: std.mem.Allocator,
        entity_id: EntityId,
        group_index: GroupIndex,
        member_index: MemberIndex,
        record_index: RecordIndex,
        inner_record: InnerEntRecord = undefined,
        set_components: std.ArrayList(ComponentIndex) = .empty,

        /// Init a new EntityRecord struct with each component index being set to null
        pub fn init(allocator: std.mem.Allocator, record_data: RecordData) !Self {
            var self: Self = .{
                .allocator = allocator,
                .entity_id = record_data.entity_id,
                .group_index = record_data.group_index,
                .member_index = record_data.member_index,
                .record_index = record_data.record_index,
                .inner_record = undefined,
            };

            try self.set_components.ensureTotalCapacity(self.allocator, Config.ComponentTags.len);

            inline for (Config.ComponentTags) |comp| @field(self.inner_record, @tagName(comp)) = null;
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.set_components.deinit(self.allocator);
            self.set_components = .empty;
        }

        pub fn setComponentIndex(self: *Self, comptime component: PoolComponent, component_index: anytype) void {
            const typeOfCompIdx = @TypeOf(component_index);
            const compIdxInfo = @typeInfo(typeOfCompIdx);
            const field = &@field(self.inner_record, @tagName(component));

            if (compIdxInfo == .optional and component_index == null) field.* = null else if (typeOfCompIdx == ComponentIndex) field.* = component_index else if (compIdxInfo == .int) field.* = ComponentIndex.init(component_index) else unreachable;
        }

        pub fn getComponentIndex(self: Self, comptime component: PoolComponent) ?ComponentIndex {
            return @field(self.inner_record, @tagName(component));
        }
    };
}

fn InnerEntityRecord(comptime TAG: PR.Enum) type {
    const Config = PR.GetPoolConfig(TAG);
    const components = Config.ComponentTags;

    var names: [components.len + 4][]const u8 = undefined;
    var types: [components.len + 4]type = undefined;
    var attrs: [components.len + 4]std.builtin.Type.StructField.Attributes = undefined;

    names[0] = "entity_id";
    types[0] = EntityId;
    attrs[0] = .{};

    names[1] = "group_index";
    types[1] = GroupIndex;
    attrs[1] = .{};

    names[2] = "member_index";
    types[2] = MemberIndex;
    attrs[2] = .{};

    names[3] = "record_index";
    types[3] = RecordIndex;
    attrs[3] = .{};

    for (components, 4..) |comp, i| {
        names[i] = @tagName(comp);
        types[i] = ?ComponentIndex;
        attrs[i] = .{};
    }

    return @Struct(
        .auto,
        null,
        &names,
        &types,
        &attrs,
    );
}
