const std = @import("std");
const Registry = @import("Registry.zig").Registry(comptime comp_descs: []const ComponentDesc)
const Arraylist = std.ArrayList;


pub fn EntPool(State: StateT) type { 
    const StorageType = blk: {
        var names: [State]
    };
    return struct {
        
    };
}
