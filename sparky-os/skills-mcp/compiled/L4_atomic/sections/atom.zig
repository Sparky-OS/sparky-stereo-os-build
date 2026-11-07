//! L4 atom: the headings of a Markdown skill and the excerpt of one section, as the Python `context` does it.
//! Fenced code blocks are ignored when looking for headings.
const std = @import("std");

pub const Heading = struct { line: usize, level: usize, title: []const u8 };

pub const Error = error{ NotFound, Ambiguous } || std.mem.Allocator.Error;

fn lineStarts(arena: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    while (start < text.len) {
        const nl = std.mem.indexOfScalarPos(u8, text, start, '\n');
        const end = if (nl) |n| n + 1 else text.len;
        try out.append(arena, text[start..end]);
        start = end;
    }
    return out.toOwnedSlice(arena);
}

pub fn headings(arena: std.mem.Allocator, text: []const u8) Error![]const Heading {
    var out: std.ArrayList(Heading) = .empty;
    var fence: ?[]const u8 = null;
    for (try lineStarts(arena, text), 0..) |line, i| {
        const stripped = std.mem.trimStart(u8, line, " \t\r\n\x0b\x0c");
        if (std.mem.startsWith(u8, stripped, "```") or std.mem.startsWith(u8, stripped, "~~~")) {
            const marker = stripped[0..3];
            if (fence) |f| {
                if (std.mem.eql(u8, f, marker)) fence = null;
            } else fence = marker;
            continue;
        }
        if (fence != null) continue;
        const l = std.mem.trimEnd(u8, line, "\n");
        var h: usize = 0;
        while (h < l.len and l[h] == '#') h += 1;
        if (h == 0 or h > 6 or h >= l.len or (l[h] != ' ' and l[h] != '\t')) continue;
        var title = std.mem.trim(u8, l[h..], " \t\r");
        title = std.mem.trimEnd(u8, title, "#");
        title = std.mem.trimEnd(u8, title, " \t");
        if (title.len == 0) continue;
        try out.append(arena, .{ .line = i, .level = h, .title = title });
    }
    return out.toOwnedSlice(arena);
}

pub fn select(arena: std.mem.Allocator, text: []const u8, title: []const u8) Error![]u8 {
    const hs = try headings(arena, text);
    var found: ?Heading = null;
    var count: usize = 0;
    for (hs) |h| if (std.mem.eql(u8, h.title, title)) {
        found = h;
        count += 1;
    };
    if (count == 0) return error.NotFound;
    if (count > 1) return error.Ambiguous;
    const f = found.?;
    const lines = try lineStarts(arena, text);
    var end: usize = lines.len;
    for (hs) |h| if (h.line > f.line and h.level <= f.level) {
        end = h.line;
        break;
    };
    var out: std.ArrayList(u8) = .empty;
    if (std.mem.startsWith(u8, text, "---\n")) {
        const before = if (std.mem.indexOf(u8, text, "\n---\n")) |i| text[0..i] else text;
        try out.appendSlice(arena, before);
        try out.appendSlice(arena, "\n---\n");
    }
    try out.appendSlice(arena, "\n[Selected section; other sections are not included.]\n\n");
    for (lines[f.line..end]) |l| try out.appendSlice(arena, l);
    return out.items;
}
