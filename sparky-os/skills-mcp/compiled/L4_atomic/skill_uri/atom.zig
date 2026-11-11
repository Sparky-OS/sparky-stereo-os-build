//! L4 atom: the address of a file of a skill, `skill://<origin>/<kind>/<name>/<file>`.
//! The last path segment before the file is the skill's name, as the Skills extension requires.
const std = @import("std");

pub const Parsed = struct { origin: []const u8, kind: []const u8, name: []const u8, file: []const u8 };

pub const scheme = "skill://";

pub fn parse(uri: []const u8) error{InvalidArgument}!Parsed {
    if (!std.mem.startsWith(u8, uri, scheme)) return error.InvalidArgument;
    var it = std.mem.splitScalar(u8, uri[scheme.len..], '/');
    const origin = it.next() orelse return error.InvalidArgument;
    const kind = it.next() orelse return error.InvalidArgument;
    const name = it.next() orelse return error.InvalidArgument;
    const file = it.rest();
    if (origin.len == 0 or kind.len == 0 or name.len == 0 or file.len == 0) return error.InvalidArgument;
    return .{ .origin = origin, .kind = kind, .name = name, .file = file };
}

pub fn format(arena: std.mem.Allocator, origin: []const u8, kind: []const u8, name: []const u8, file: []const u8) ![]u8 {
    return std.fmt.allocPrint(arena, "skill://{s}/{s}/{s}/{s}", .{ origin, kind, name, file });
}
