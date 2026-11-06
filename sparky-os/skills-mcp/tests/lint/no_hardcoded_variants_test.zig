//! Halt condition: "a new variant is hardcoded in a parent instead of dropped into `_kinds/`".
//! A variant id of five or more characters (the ids "user" and "en" are too common as words to be searched for)
//! must not appear as a quoted string anywhere under compiled/ or surfaces/ outside the _kinds/ folders.
const std = @import("std");
const registries = .{
    @import("kinds_era"),     @import("kinds_tool"),
    @import("kinds_assistant"), @import("kinds_skill_kind"),
    @import("kinds_lang"),
};

/// Comment lines may mention a variant to explain it; only code is searched.
fn withoutComments(gpa: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |l| {
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, l, " \t"), "//")) continue;
        try out.appendSlice(gpa, l);
        try out.append(gpa, '\n');
    }
    return out.toOwnedSlice(gpa);
}

test "no parent names a variant" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const gpa = arena_state.allocator();
    const io = std.testing.io;
    var examined: usize = 0;
    for ([_][]const u8{ "compiled", "surfaces" }) |top| {
        var dir = try std.Io.Dir.cwd().openDir(io, top, .{ .iterate = true });
        defer dir.close(io);
        var walker = try dir.walk(gpa);
        defer walker.deinit();
        while (try walker.next(io)) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.path, ".zig")) continue;
            if (std.mem.indexOf(u8, e.path, "_kinds") != null) continue;
            const raw = try dir.readFileAlloc(io, e.path, gpa, .limited(1 << 20));
            const src = try withoutComments(gpa, raw);
            examined += 1;
            inline for (registries) |reg| for (reg.names) |n| {
                if (n.len < 5) continue;
                const quoted = try std.fmt.allocPrint(gpa, "\"{s}\"", .{n});
                if (std.mem.indexOf(u8, src, quoted) != null) {
                    std.debug.print("{s}/{s}: hardcodes the variant {s}\n", .{ top, e.path, n });
                    return error.VariantHardcoded;
                }
            };
        }
    }
    try std.testing.expect(examined > 0);
}
