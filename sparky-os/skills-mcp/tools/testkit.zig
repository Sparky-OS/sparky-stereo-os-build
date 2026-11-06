//! Test helpers: a scratch folder under /tmp (the runner mounts a tmpfs there; the product tree is read only),
//! files written into it, and an environment map for the engine.
const std = @import("std");

pub const Scratch = struct {
    dir: std.Io.Dir,
    path: []const u8,
    io: std.Io,

    pub fn make(io: std.Io, path: []const u8) !Scratch {
        std.Io.Dir.cwd().deleteTree(io, path) catch {};
        return .{ .dir = try std.Io.Dir.cwd().createDirPathOpen(io, path, .{}), .path = path, .io = io };
    }

    pub fn cleanup(self: *Scratch) void {
        self.dir.close(self.io);
        std.Io.Dir.cwd().deleteTree(self.io, self.path) catch {};
    }

    pub fn write(self: Scratch, rel: []const u8, content: []const u8) !void {
        if (std.fs.path.dirname(rel)) |d| try self.dir.createDirPath(self.io, d);
        try self.dir.writeFile(self.io, .{ .sub_path = rel, .data = content });
    }

    pub fn remove(self: Scratch, rel: []const u8) !void {
        try self.dir.deleteTree(self.io, rel);
    }

    pub fn abs(self: Scratch, arena: std.mem.Allocator, rel: []const u8) ![]u8 {
        return std.fmt.allocPrint(arena, "{s}/{s}", .{ self.path, rel });
    }
};

pub fn skill(arena: std.mem.Allocator, name: []const u8, description: []const u8, requires: []const u8) ![]u8 {
    if (requires.len == 0) return std.fmt.allocPrint(arena, "---\nname: {s}\ndescription: {s}\n---\n\n# {s}\n\nBody.\n", .{ name, description, name });
    return std.fmt.allocPrint(arena, "---\nmetadata:\n  requires-packages: {s}\nname: {s}\ndescription: {s}\n---\n\n# {s}\n\nBody.\n", .{ requires, name, description, name });
}

pub fn env(arena: std.mem.Allocator, pairs: []const [2][]const u8) !*std.process.Environ.Map {
    const m = try arena.create(std.process.Environ.Map);
    m.* = std.process.Environ.Map.init(arena);
    for (pairs) |p| try m.put(p[0], p[1]);
    return m;
}
