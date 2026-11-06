//! L4 atom: the person's saved choices, `KEY=value` lines in ~/.config/sparky-stereo-skills/state.
//! The helper already keeps `LINK`-style keys in the same file, so every key this atom does not touch is kept byte for byte.
const std = @import("std");

pub fn get(text: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var found: ?[]const u8 = null;
    while (lines.next()) |l| {
        if (l.len > key.len and std.mem.startsWith(u8, l, key) and l[key.len] == '=') found = std.mem.trim(u8, l[key.len + 1 ..], " \t\r\"'");
    }
    return found;
}

/// The text with `key` set to `value` (replacing the first line of that key and dropping repeats, or appended);
/// `value` of null removes the key. Every other line, blank lines included, is kept as it was.
pub fn set(arena: std.mem.Allocator, text: []const u8, key: []const u8, value: ?[]const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;
    var wrote = false;
    if (text.len > 0) {
        var lines = std.mem.splitScalar(u8, body, '\n');
        while (lines.next()) |l| {
            if (l.len > key.len and std.mem.startsWith(u8, l, key) and l[key.len] == '=') {
                if (value) |v| if (!wrote) {
                    try out.print(arena, "{s}={s}\n", .{ key, v });
                    wrote = true;
                };
                continue;
            }
            try out.appendSlice(arena, l);
            try out.append(arena, '\n');
        }
    }
    if (value) |v| if (!wrote) try out.print(arena, "{s}={s}\n", .{ key, v });
    return out.items;
}
