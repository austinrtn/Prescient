const std = @import("std");

pub const ComponentDesc = struct {
    name: []const u8,
    T: type,
};

pub fn ComponentTypes(comptime comp_descs: []const ComponentDesc) type {
    var names: [comp_descs.len][]const u8 = undefined;
    var types: [comp_descs.len]type = undefined;
    var attrs: [comp_descs.len]std.builtin.Type.StructField.Attributes = undefined;

    for(comp_descs, 0..) |desc, i| {
        names[i] = desc.name;
        types[i] = desc.T;
    }

    return @Struct(
        .auto,
        null,
        &names,
        &types,
        &attrs,
    );
}

pub fn ComponentEnumT(comptime comp_descs: []const ComponentDesc) type {
    var names: [comp_descs.len][]const u8 = undefined;
    var vals:[comp_descs.len]u8 = undefined;

    for(comp_descs, 0..) |desc, i| {
        names[i] = desc.name;
        vals[i] = @intCast(i);
    }

    return @Enum(
        u8,
        .exhaustive,
        &names,
        &vals,
    );
}

fn stringTypeMap(comptime comp_descs: []const ComponentDesc) std.StaticStringMap(type) {
    const KV = struct{[]const u8, type};
    var values: [comp_descs.len]KV = undefined;

    for(comp_descs, 0..) |desc, i| {
        values[i] = .{desc.name, desc.T};
    }

    return std.StaticStringMap(type).initComptime(values);
}

pub fn ComponentRegistry(comptime comp_descs: []const ComponentDesc) type {
    return struct {
        pub const Count = comp_descs.len;
        pub const Types = ComponentTypes(comp_descs);
        pub const Enum = ComponentEnumT(comp_descs);
        pub const BitSet = std.StaticBitSet(comp_descs.len);
        const string_type_map = stringTypeMap(comp_descs);

        pub fn GetTypeByField(comptime component: Enum) type {
            return string_type_map.get(@tagName(component)) orelse unreachable;
        }

        pub fn getBitmaskOfComponents(comptime components: []const Enum) BitSet {
            var mask: BitSet = .empty;
            for(components) |comp| mask.set(@intFromEnum(comp));
            return mask;
        }

        pub fn getComponentsFromType(comptime EntType: type) [std.meta.fields(EntType).len]Enum {
            const ent_fields = std.meta.fields(EntType);
            var comps: [ent_fields.len]Enum = undefined;

            inline for(ent_fields, 0..) |field, i| {
                comps[i] = std.meta.stringToEnum(Enum, field.name) orelse unreachable;
            }
            return comps;
        }

        pub fn GetTypeOfComponents(comptime components: []const Enum, comptime get_slices: bool) type {
            var names: [components.len][]const u8 = undefined;
            var types: [components.len]type = undefined;
            var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

            for(components, 0..) |comp, i| {
                const CompType = GetTypeByField(comp);
                const T = if(get_slices) []CompType else CompType;
                names[i] = @tagName(comp);
                types[i] = T;
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
    };
}
