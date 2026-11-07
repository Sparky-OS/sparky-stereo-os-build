//! A variant is a file dropped into a _kinds/ folder; none is written into a parent.
//! Drop-a-file: adding a file to a registry folder adds a variant, removing it removes it, nothing else changes.
const std = @import("std");
const scan = @import("kinds_scan");

/// A scratch folder under /tmp (the runner mounts a tmpfs there); the product tree itself is read only.
const Scratch = struct {
    dir: std.Io.Dir,
    path: []const u8,
    io: std.Io,

    fn make(io: std.Io, path: []const u8) !Scratch {
        std.Io.Dir.cwd().deleteTree(io, path) catch {};
        return .{ .dir = try std.Io.Dir.cwd().createDirPathOpen(io, path, .{}), .path = path, .io = io };
    }

    fn cleanup(self: *Scratch) void {
        self.dir.close(self.io);
        std.Io.Dir.cwd().deleteTree(self.io, self.path) catch {};
    }
};

fn touch(io: std.Io, dir: std.Io.Dir, name: []const u8) !void {
    var f = try dir.createFile(io, name, .{});
    f.close(io);
}

test "a registry lists its files sorted, ignoring files that are not .zig" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = try Scratch.make(io, "/tmp/skills-mcp-kinds-0");
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "_kinds", .default_dir);
    var k = try tmp.dir.openDir(io, "_kinds", .{});
    defer k.close(io);
    try touch(io, k, "zeta.zig");
    try touch(io, k, "alpha.zig");
    try touch(io, k, "notes.md");
    const names = try scan.list(a, io, tmp.dir, "_kinds");
    defer scan.free(a, names);
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("alpha", names[0]);
    try std.testing.expectEqualStrings("zeta", names[1]);
}

test "dropping a third file adds exactly one variant; removing it takes it away" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = try Scratch.make(io, "/tmp/skills-mcp-kinds-1");
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "_kinds", .default_dir);
    var k = try tmp.dir.openDir(io, "_kinds", .{});
    defer k.close(io);
    try touch(io, k, "one.zig");
    try touch(io, k, "two.zig");
    const before = try scan.list(a, io, tmp.dir, "_kinds");
    defer scan.free(a, before);
    try touch(io, k, "three.zig");
    const after = try scan.list(a, io, tmp.dir, "_kinds");
    defer scan.free(a, after);
    try std.testing.expectEqual(before.len + 1, after.len);
    try k.deleteFile(io, "three.zig");
    const back = try scan.list(a, io, tmp.dir, "_kinds");
    defer scan.free(a, back);
    try std.testing.expectEqual(before.len, back.len);
}

test "a missing registry is empty, an unreadable one is an error" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = try Scratch.make(io, "/tmp/skills-mcp-kinds-2");
    defer tmp.cleanup();
    const none = try scan.list(a, io, tmp.dir, "no/such/registry");
    defer scan.free(a, none);
    try std.testing.expectEqual(@as(usize, 0), none.len);
    try touch(io, tmp.dir, "afile");
    try std.testing.expectError(error.ScanFailed, scan.list(a, io, tmp.dir, "afile"));
}

test "the real registries are the ones the plan names" {
    try std.testing.expectEqual(@as(usize, 2), @import("kinds_era").names.len);
    try std.testing.expectEqual(@as(usize, 2), @import("kinds_skill_kind").names.len);
    try std.testing.expectEqual(@as(usize, 9), @import("kinds_lang").names.len);
}
