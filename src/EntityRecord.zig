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
        entity_id: EntityId,
        group_index: GroupIndex,
        member_index: MemberIndex,
        record_index: RecordIndex,
        inner_record: InnerEntRecord = undefined,

        /// Init a new EntityRecord struct with each component index being set to null
        pub fn init(record_data: RecordData) Self {
            var self: Self = .{
                .entity_id = record_data.entity_id,
                .group_index = record_data.group_index,
                .member_index = record_data.member_index,
                .record_index = record_data.record_index,
                .inner_record = undefined,
            };

            inline for (Config.ComponentTags) |comp| @field(self.inner_record, @tagName(comp)) = null;
            return self;
        }

        pub fn setComponentIndex(self: *Self, comptime component: PoolComponent, component_index: anytype) void {
            const typeOf = @TypeOf(component_index);
            const info = @typeInfo(typeOf);
            
            if(typeOf == ComponentIndex) @field(self.inner_record, @tagName(component)) = component_index
            else if(info == .int) @field(self.inner_record, @tagName(component)) = ComponentIndex.init(component_index)
            else unreachable;
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
