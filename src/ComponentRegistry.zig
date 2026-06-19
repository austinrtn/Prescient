const std = @import("std");
const Registry = @import("Registry.zig").Registry;

pub const ComponentRegistry = ComponentRegistryT(&Registry.comp_descs);

pub const ComponentDesc = struct {
    name: []const u8,
    T: type,
};

pub fn ComponentRegistryT(comptime comp_descs: []const ComponentDesc) type {
    return struct {
        pub const Count = comp_descs.len;
        pub const Types = ComponentTypes(comp_descs);
        pub const Enum = ComponentEnumT(comp_descs);
        pub const BitSet = std.StaticBitSet(comp_descs.len);
        
        const string_type_map = stringTypeMap(comp_descs);

        pub fn getCompTypeByEnum(comptime component: Enum) type {
            return string_type_map.get(@tagName(component)) orelse unreachable;
        }
        
        pub fn GetCompTypeByName(comptime component: []const u8) type {
            return string_type_map.get(component) orelse unreachable;
        }

        pub fn getEnumByName(comptime component_name: []const u8) Enum {
            return std.meta.stringToEnum(Enum, component_name) orelse 
                @compileError("Component " ++ component_name ++ " does not exist in registry");
        }

        pub fn getBitmaskOfComponents(comptime components: []const Enum) BitSet {
            var mask: BitSet = .empty;
            for(components) |comp| mask.set(@intFromEnum(comp));
            return mask;
        }
        
        pub fn maskContainsComponent(comptime component: Enum, mask: BitSet) bool {
            return mask.isSet(@intFromEnum(component));
        }
                
        pub fn getComponentsFromMask(mask: BitSet, comp_buf: []Enum) []Enum {
            var i: usize = 0;
            var set_bits: usize = 0;
            while(i < Count) : (i += 1) {
                if(mask.isSet(i)) {
                    comp_buf[i] = @enumFromInt(i);
                    set_bits += 1;
                }
            }
            
            return comp_buf[0..set_bits];
        }

        pub fn getComponentsFromType(comptime EntType: type) [std.meta.fields(EntType).len]Enum {
            const ent_fields = std.meta.fields(EntType);
            var comps: [ent_fields.len]Enum = undefined;

            inline for(ent_fields, 0..) |field, i| {
                comps[i] = std.meta.stringToEnum(Enum, field.name) orelse unreachable;
            }
            return comps;
        }

        pub fn getBitmaskFromEnt(comptime EntType: type) BitSet {
            const comps = getComponentsFromType(EntType);
            return getBitmaskOfComponents(&comps);
        }

        pub fn addComponentBit(comptime component: Enum, bitset: BitSet) BitSet {
            var new_bitset = bitset;
            new_bitset.set(getBitByEnum(component));
            return new_bitset;
        }

        pub fn getBitByEnum(comptime component: Enum) usize {
            return @intFromEnum(component);
        }

        pub fn EntTypeToCompStruct(comptime EntType: type) type {
            const fields = std.meta.fields(EntType);
            var names: [fields.len][]const u8 = undefined;
            var types: [fields.len]type = undefined;
            var attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;
            
            for (fields, 0..) |field, i| {
                names[i] = field.name;
                types[i] = GetCompTypeByName(field.name);
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

        pub fn AnomToTypedComponentStruct(anom_ent: anytype) EntTypeToCompStruct(@TypeOf(anom_ent)){
            const EntType = @TypeOf(anom_ent);
            var container: EntTypeToCompStruct(EntType) = undefined;

            inline for(std.meta.fields(EntType)) |field| {
                const anom_comp = @field(anom_ent, field.name);
                @field(container, field.name) = convertAnomToComponent(anom_comp, field.name);
            }

            return container;
        }

        pub fn convertAnomToComponent(anom: anytype, comptime comp_name: []const u8) GetCompTypeByName(comp_name) {
            const AnomType = @TypeOf(anom);
            const CompType = GetCompTypeByName(comp_name); 
            var comp: CompType = undefined; 
            
            if(@typeInfo(CompType) == .@"struct") {
                inline for(std.meta.fields(CompType)) |field| {
                    if(!@hasField(AnomType, field.name)) {
                        @compileError("Anom Component " ++ comp_name ++ " is missing field: " ++ field.name);
                    }
                    @field(comp, field.name) = @field(anom, field.name);
                }
            } else comp = anom;

            return comp;
        }

        pub fn GetTypeOfComponents(comptime components: []const Enum, comptime get_slices: bool) type {
            var names: [components.len][]const u8 = undefined;
            var types: [components.len]type = undefined;
            var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;

            inline for(components, 0..) |comp, i| {
                const CompType = getCompTypeByEnum(comp);
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

        fn MaskToPartialComponentStruct(comptime components: []const Enum) type {
            var names: [components.len][]const u8 = undefined;
            var types: [components.len]type = undefined;
            var attrs: [components.len]std.builtin.Type.StructField.Attributes = undefined;
            
            inline for (components, 0..) |comp, i| {
                const T = getCompTypeByEnum(comp);
                names[i] = @tagName(comp);
                types[i] = ?T;
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
        
        pub fn initMaskToPartialComponentStruct(comptime components: []const Enum) MaskToPartialComponentStruct(components) {
            var build: MaskToPartialComponentStruct(components) = undefined;

            inline for(components) |comp| {
                @field(build, @tagName(comp)) = null;
            }

            return build;
        }
    };
}

 fn ComponentTypes(comptime comp_descs: []const ComponentDesc) type {
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

 fn ComponentEnumT(comptime comp_descs: []const ComponentDesc) type {
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
