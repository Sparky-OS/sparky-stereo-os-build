//! The drop-a-file scanner. A registry is a folder `_kinds/<registry>/`; each `*.zig` file in it is one variant.
//! build.zig and the tests use this one function, so the build and the test agree on what a registry holds.
const std = @import("std");

pub const Error = std.mem.Allocator.Error || error{ScanFailed};

/// Names (without `.zig`) of the variants in `sub_path` of `dir`, sorted, so the generated registry is deterministic.
/// A missing folder is an empty registry; any other failure is reported, never taken for "empty".
pub fn list(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, sub_path: []const u8) Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    var d = dir.openDir(io, sub_path, .{ .iterate = true }) catch |e| switch (e) {
        error.FileNotFound => return names.toOwnedSlice(gpa),
        else => return error.ScanFailed,
    };
    defer d.close(io);
    var it = d.iterate();
    while (it.next(io) catch return error.ScanFailed) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
        const stem = entry.name[0 .. entry.name.len - 4];
        try names.append(gpa, try gpa.dupe(u8, stem));
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    return names.toOwnedSlice(gpa);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

pub fn free(gpa: std.mem.Allocator, names: []const []const u8) void {
    for (names) |n| gpa.free(n);
    gpa.free(names);
}
