//! L5 operation: one file of one skill, for `resources/read` and the `skills_read` tool.
//! Read only, inside the skill's own folder after every symlink is resolved, at most 256 KiB, valid UTF-8.
const std = @import("std");
const fsio = @import("fsio");
const pathsafe = @import("pathsafe");
const skill_record = @import("skill_record");

pub const max_bytes: usize = 256 * 1024;

pub const Error = error{ Refused, TooLarge, NotText, NotFound } || std.mem.Allocator.Error;

pub fn run(arena: std.mem.Allocator, io: std.Io, rec: skill_record.Rec, rel: []const u8) Error![]u8 {
    _ = pathsafe.check(rel) catch return error.Refused;
    const joined = try std.fmt.allocPrint(arena, "{s}/{s}", .{ rec.dir, rel });
    const real = fsio.realPath(arena, io, joined) catch return error.NotFound;
    const root = fsio.realPath(arena, io, rec.dir) catch return error.NotFound;
    pathsafe.checkResolved(root, real) catch return error.Refused;
    const bytes = fsio.readFile(arena, io, real, max_bytes) catch |e| switch (e) {
        error.StreamTooLong => return error.TooLarge,
        else => return if (e == error.OutOfMemory) e else error.NotFound,
    };
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.NotText;
    return bytes;
}
