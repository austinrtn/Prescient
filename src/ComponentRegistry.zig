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

pub fn ComponentRegistry(comptime comp_descs: []const ComponentDesc) type {
    return struct {
        pub const Count = comp_descs.len;
        pub const Types = ComponentTypes(comp_descs);
        pub const Enums = ComponentEnumT(comp_descs);
    };
}