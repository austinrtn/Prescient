const std = @import("std");
const ArrayList = std.ArrayList;
const File = std.fs.File;

pub const FileWriter = struct {
    const Self = @This();

    fileContent: ArrayList(u8) = .empty,
    file: ?File = null,
    filePath: []const u8,

    pub fn getContent(self: *Self) []u8 {
        return self.fileContent.items;
    }

    pub fn write(self: *Self, allocator: std.mem.Allocator, text: []const u8) !void {
        try self.fileContent.appendSlice(allocator, text);
    }

    pub fn writeFmt(self: *Self, allocator: std.mem.Allocator, comptime text: []const u8, args: anytype) !void {
        const formatted = try std.fmt.allocPrint(allocator, text, args);
        defer allocator.free(formatted);
        try self.write(allocator, formatted);
    }

    pub fn writeLine(self: *Self, allocator: std.mem.Allocator, text: []const u8) !void {
        try self.write(allocator, text);
        try self.write(allocator, "\n");
    }

    pub fn saveFile(self: *Self) !void {
        if (self.file == null) {
            self.file = try std.fs.cwd().createFile(self.filePath, .{});
        }
        try self.file.?.writeAll(self.fileContent.items);
    }

    pub fn saveAndClose(self: *Self, allocator: std.mem.Allocator) void {
        self.saveFile() catch {};
        self.deinit(allocator);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.fileContent.deinit(allocator);
        if (self.file) |file| {
            file.close();
        }
    }
};
