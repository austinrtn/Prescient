const std = @import("std");
const ArrayList = std.ArrayList;
const print = std.debug.print;
const FileWriter = @import("FileWriter.zig").FileWriter;

/// Registry builder for Prescient ECS
/// Scans component/system directories and generates registry files
/// Also creates PoolRegistry.zig template if it doesn't exist

const FileData = struct {
    typeName: []const u8,
    fileName: []const u8,
};

const FileStorage = struct {
    fileData: ArrayList(FileData) = .empty,
    fileWriter: FileWriter,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.fileData.items) |data| {
            allocator.free(data.typeName);
            allocator.free(data.fileName);
        }
        self.fileData.deinit(allocator);
        self.fileWriter.deinit(allocator);
    }
};

pub fn main() !void {
    print("\n=======================\n", .{});
    print("Building Registries....\n", .{});
    print("=======================\n\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    const project_dir = args.next() orelse {
        print("Error: Project directory not provided.\n", .{});
        return error.MissingProjectDir;
    };

    // Ensure registries directory exists
    const registries_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries" });
    defer allocator.free(registries_dir);

    std.fs.cwd().makePath(registries_dir) catch |err| {
        print("Error creating registries directory: {}\n", .{err});
        return err;
    };
    print("Ensured registries directory exists: {s}\n\n", .{registries_dir});

    // Build ComponentRegistry.zig
    try buildRegistry(allocator, project_dir, "components", "ComponentRegistry.zig", "Component");

    // Build SystemRegistry.zig
    try buildRegistry(allocator, project_dir, "systems", "SystemRegistry.zig", "System");

    // Check/create PoolRegistry.zig
    try ensurePoolRegistry(allocator, project_dir);

    print("\n=======================\n", .{});
    print("Registries built!\n", .{});
    print("=======================\n\n", .{});
}

fn buildRegistry(
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    directoryName: []const u8,
    registryName: []const u8,
    varName: []const u8,
) !void {
    const directoryPath = try std.fs.path.join(allocator, &.{ project_dir, "src", directoryName });
    defer allocator.free(directoryPath);

    const registryPath = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", registryName });
    defer allocator.free(registryPath);

    var fileStorage = FileStorage{ .fileWriter = .{ .filePath = registryPath } };
    defer fileStorage.deinit(allocator);

    print("Scanning {s} directory: {s}\n", .{ varName, directoryPath });

    const filesFound = getFileData(allocator, &fileStorage, directoryPath) catch |err| {
        if (err == error.FileNotFound) {
            print("  Directory does not exist. Creating empty registry.\n", .{});
            try writeEmptyRegistry(allocator, &fileStorage, varName);
            try fileStorage.fileWriter.saveFile();
            return;
        }
        return err;
    };

    if (!filesFound) {
        print("  No .zig files found. Creating empty registry.\n", .{});
        try writeEmptyRegistry(allocator, &fileStorage, varName);
        try fileStorage.fileWriter.saveFile();
        return;
    }

    print("  Found {} files.\n", .{fileStorage.fileData.items.len});

    try writeImports(allocator, &fileStorage, directoryName);

    // Only generate compTypes for ComponentRegistry, not SystemRegistry
    if (std.mem.eql(u8, varName, "Component")) {
        try writeCompTypes(allocator, &fileStorage, directoryName);
    }

    try writeDataStructures(allocator, &fileStorage, varName);

    try fileStorage.fileWriter.saveFile();
    print("  Generated: {s}\n", .{registryPath});
}

fn getFileData(allocator: std.mem.Allocator, fs: *FileStorage, directory: []const u8) !bool {
    var dir = std.fs.cwd().openDir(directory, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return err;
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const file = try dir.openFile(entry.name, .{});
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(content);

            // Parse type name from file (struct, enum, union, or type alias)
            const typeName = parseTypeName(content) orelse {
                print("  Warning: No type definition found in {s}, skipping.\n", .{entry.name});
                continue;
            };

            const fileData = FileData{
                .typeName = try allocator.dupe(u8, typeName),
                .fileName = try allocator.dupe(u8, entry.name),
            };
            try fs.fileData.append(allocator, fileData);
        }
    }

    // Sort by type name for consistent ordering
    std.mem.sort(FileData, fs.fileData.items, {}, struct {
        fn lessThan(_: void, a: FileData, b: FileData) bool {
            return std.mem.lessThan(u8, a.typeName, b.typeName);
        }
    }.lessThan);

    return fs.fileData.items.len > 0;
}

fn parseTypeName(content: []const u8) ?[]const u8 {
    var lines = std.mem.splitAny(u8, content, "\n");

    while (lines.next()) |line| {
        // Look for "pub const Name = struct/enum/union" or "pub const Name = SomeType;"
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r\n");

        var token_index: usize = 0;
        var found_pub = false;
        var found_const = false;
        var name: ?[]const u8 = null;
        var found_equals = false;

        while (tokens.next()) |token| {
            if (token_index == 0 and std.mem.eql(u8, token, "pub")) {
                found_pub = true;
            } else if (token_index == 1 and found_pub and std.mem.eql(u8, token, "const")) {
                found_const = true;
            } else if (token_index == 2 and found_const) {
                name = token;
            } else if (token_index == 3 and name != null and std.mem.eql(u8, token, "=")) {
                found_equals = true;
            } else if (token_index == 4 and name != null and found_equals) {
                // Check for struct, enum, union (with or without trailing brace)
                if (std.mem.eql(u8, token, "struct") or std.mem.startsWith(u8, token, "struct{") or
                    std.mem.eql(u8, token, "enum") or std.mem.startsWith(u8, token, "enum{") or std.mem.startsWith(u8, token, "enum(") or
                    std.mem.eql(u8, token, "union") or std.mem.startsWith(u8, token, "union{") or std.mem.startsWith(u8, token, "union("))
                {
                    return name;
                }
                // Check for type alias (e.g., "pub const Color = u32;")
                // Token should end with semicolon or be a type name
                if (std.mem.endsWith(u8, token, ";") or isTypeName(token)) {
                    return name;
                }
            }
            token_index += 1;
        }
    }
    return null;
}

fn isTypeName(token: []const u8) bool {
    // Check for primitive types
    const primitives = [_][]const u8{
        "u8",    "u16",   "u32",   "u64",   "u128",  "usize",
        "i8",    "i16",   "i32",   "i64",   "i128",  "isize",
        "f16",   "f32",   "f64",   "f128",
        "bool",  "void",  "noreturn",
        "c_int", "c_uint", "c_long", "c_ulong",
    };

    for (primitives) |prim| {
        if (std.mem.eql(u8, token, prim)) return true;
    }

    // Check for user-defined types (starts with uppercase, or contains a dot for namespaced types)
    if (token.len > 0) {
        const first = token[0];
        if (first >= 'A' and first <= 'Z') return true;
        if (std.mem.indexOf(u8, token, ".") != null) return true;
    }

    return false;
}

fn writeEmptyRegistry(allocator: std.mem.Allocator, fs: *FileStorage, varName: []const u8) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeFmt(allocator, "// Generated by: zig build registry\n", .{});
    try fs.fileWriter.writeFmt(allocator, "// Add {s}s to src/{s}s/ and rebuild\n", .{ varName, varName });
    try fs.fileWriter.writeLine(allocator, "");

    // Only generate compTypes for ComponentRegistry, not SystemRegistry
    if (std.mem.eql(u8, varName, "Component")) {
        try fs.fileWriter.writeLine(allocator, "pub const compTypes = struct {};");
        try fs.fileWriter.writeLine(allocator, "");
    }

    try fs.fileWriter.writeFmt(allocator, "pub const {s}Name = enum {{\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeFmt(allocator, "pub const {s}Types = [_]type {{\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");

    // Build the lowercase version properly
    var lowercase_first: [1]u8 = undefined;
    _ = std.ascii.lowerString(&lowercase_first, varName[0..1]);
    try fs.fileWriter.writeFmt(allocator, "pub fn getTypeByName(comptime {c}{s}_name: {s}Name) type {{\n", .{ lowercase_first[0], varName[1..], varName });
    try fs.fileWriter.writeFmt(allocator, "    const index = @intFromEnum({c}{s}_name);\n", .{ lowercase_first[0], varName[1..] });
    try fs.fileWriter.writeFmt(allocator, "    return {s}Types[index];\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "}");
}

fn writeImports(allocator: std.mem.Allocator, fs: *FileStorage, directoryName: []const u8) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "");

    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "pub const {s} = @import(\"../{s}/{s}\").{s};\n",
            .{ data.typeName, directoryName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeCompTypes(allocator: std.mem.Allocator, fs: *FileStorage, directoryName: []const u8) !void {
    try fs.fileWriter.writeLine(allocator, "pub const compTypes = struct {");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "    pub const {s} = @import(\"../{s}/{s}\").{s};\n",
            .{ data.typeName, directoryName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeDataStructures(allocator: std.mem.Allocator, fs: *FileStorage, varName: []const u8) !void {
    // Write enum
    try fs.fileWriter.writeFmt(allocator, "pub const {s}Name = enum {{\n", .{varName});
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");

    // Write types array
    try fs.fileWriter.writeFmt(allocator, "pub const {s}Types = [_]type {{\n", .{varName});
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");

    // Write getTypeByName function
    var lowercase_first: [1]u8 = undefined;
    _ = std.ascii.lowerString(&lowercase_first, varName[0..1]);
    try fs.fileWriter.writeFmt(allocator, "pub fn getTypeByName(comptime {c}{s}_name: {s}Name) type {{\n", .{ lowercase_first[0], varName[1..], varName });
    try fs.fileWriter.writeFmt(allocator, "    const index = @intFromEnum({c}{s}_name);\n", .{ lowercase_first[0], varName[1..] });
    try fs.fileWriter.writeFmt(allocator, "    return {s}Types[index];\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "}");
}

fn ensurePoolRegistry(allocator: std.mem.Allocator, project_dir: []const u8) !void {
    const poolRegistryPath = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", "PoolRegistry.zig" });
    defer allocator.free(poolRegistryPath);

    // Check if PoolRegistry.zig exists
    if (std.fs.cwd().access(poolRegistryPath, .{})) |_| {
        print("\nPoolRegistry.zig exists, skipping.\n", .{});
        return;
    } else |_| {}

    print("\nPoolRegistry.zig not found. Creating template...\n", .{});

    var writer = FileWriter{ .filePath = poolRegistryPath };
    defer writer.deinit(allocator);

    const template =
        \\const std = @import("std");
        \\const cr = @import("ComponentRegistry.zig");
        \\const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
        \\const StorageStrategy = @import("../ecs/StorageStrategy.zig").StorageStrategy;
        \\
        \\// GeneralPool - includes all registered components
        \\const general_components = std.meta.tags(cr.ComponentName);
        \\pub const GeneralPool = EntityPool(.{
        \\    .name = .GeneralPool,
        \\    .components = general_components,
        \\    .storage_strategy = .SPARSE,
        \\});
        \\
        \\// Add more pools below...
        \\
        \\pub const PoolName = enum(u32) {
        \\    GeneralPool,
        \\    // Add more pool names here
        \\};
        \\
        \\pub const pool_types = [_]type{
        \\    GeneralPool,
        \\    // Add more pools here
        \\};
        \\
        \\pub fn getPoolFromName(comptime pool: PoolName) type {
        \\    return pool_types[@intFromEnum(pool)];
        \\}
        \\
        \\/// Check at compile time if a pool contains a specific component
        \\pub fn poolHasComponent(comptime pool_name: PoolName, comptime component: cr.ComponentName) bool {
        \\    const PoolType = getPoolFromName(pool_name);
        \\    const pool_components = PoolType.COMPONENTS;
        \\
        \\    for (pool_components) |comp| {
        \\        if (comp == component) {
        \\            return true;
        \\        }
        \\    }
        \\    return false;
        \\}
        \\
        \\pub const PoolConfig = struct {
        \\    name: PoolName,
        \\    req: ?[]const cr.ComponentName = null,
        \\    components: ?[]const cr.ComponentName = null,
        \\    storage_strategy: StorageStrategy,
        \\};
        \\
    ;

    try writer.write(allocator, template);
    try writer.saveFile();
    print("  Created: {s}\n", .{poolRegistryPath});
}
