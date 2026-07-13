const std = @import("std");
const TestPackage = @import("TestInstance.zig").GetPkg;
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

    const SetComponentIterator = struct {
        pub const Self = @This();

        set_components: [Config.ComponentTags.len]PoolComponent,
        set_count: usize,
        index: usize = 0,

        pub fn next(
            self: *Self,
        ) ?PoolComponent {
            if (self.index == self.set_count) {
                self.reset();
                return null;
            } else {
                defer self.index += 1;
                return self.set_components[self.index];
            }
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }
    };

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

        set_components: [Config.ComponentTags.len]PoolComponent = undefined,
        set_count: usize = 0,

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
            const typeOfCompIdx = @TypeOf(component_index);
            const compIdxInfo = @typeInfo(typeOfCompIdx);
            const field = &@field(self.inner_record, @tagName(component));

            //      0    1    2    3   [count: 4]   4      5     6
            //<SET>pos, foo, bar, vel</SET><UNSET>color, shape, size,

            if (compIdxInfo == .optional and component_index == null) {
                if (field.* != null) {
                    const idx = std.mem.findScalar(component, self.set_components, component) orelse unreachable;
                    self.set_components[idx] = self.set_components[self.set_count - 1];
                    self.count -= 1;
                }

                field.* = null;
            } else {
                if (field.* == null) {
                    self.set_components[self.set_count] = component;
                    self.set_count += 1;
                }

                if (typeOfCompIdx == ComponentIndex) {
                    field.* = component_index;
                } else if (compIdxInfo == .int) {
                    field.* = ComponentIndex.init(component_index);
                } else {
                    @compileError("setComponentIndex expected null, ComponentIndex, or an integer index");
                }
            }
        }

        pub fn getComponentIndex(self: Self, comptime component: PoolComponent) ?ComponentIndex {
            return @field(self.inner_record, @tagName(component));
        }

        pub fn iter(self: *Self) SetComponentIterator {
            return .{
                .set_components = self.set_components,
                .set_count = self.set_count,
            };
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

test "EntityRecord" {
    const prescient, const arch_pool, _, _, _ = try TestPackage();
    
    defer prescient.deinit();
    _ = arch_pool;
}
