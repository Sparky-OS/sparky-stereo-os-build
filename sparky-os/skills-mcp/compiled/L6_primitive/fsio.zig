//! L6 primitive: read-only file access. Files are opened read only; nothing here writes except `writeNew`.
const std = @import("std");

pub const Kind = enum { file, directory, other };
pub const Entry = struct { name: []const u8, kind: Kind };

pub fn readFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8, max: usize) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max));
}

/// Entries of a directory sorted by name. A missing directory is `error.FileNotFound`, the caller decides what that means.
pub fn listDir(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![]Entry {
    var d = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer d.close(io);
    var out: std.ArrayList(Entry) = .empty;
    var it = d.iterate();
    while (try it.next(io)) |e| {
        const kind: Kind = switch (e.kind) {
            .file => .file,
            .directory => .directory,
            else => .other,
        };
        try out.append(gpa, .{ .name = try gpa.dupe(u8, e.name), .kind = kind });
    }
    std.mem.sort(Entry, out.items, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    return out.toOwnedSlice(gpa);
}

pub fn exists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

/// The path with every symlink resolved.
pub fn realPath(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    const p = try std.Io.Dir.cwd().realPathFileAlloc(io, path, gpa);
    return p;
}

/// Creates `path` (and its parents) and writes `bytes` to it, replacing it. Used only for the person's own state file.
pub fn writeReplace(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |dir| try cwd.createDirPath(io, dir);
    try cwd.writeFile(io, .{ .sub_path = path, .data = bytes });
}
