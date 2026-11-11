//! Equality with the Python engine: for the recorded queries, `find` returns the same skills in the same order with
//! the same score to two decimals (data/golden/find-symptoms.tsv, recorded from the Python engine this one replaced).
//! The skills checkout is given with -Dskills-src; without it the test fails, a skipped oracle proves nothing.
const std = @import("std");
const options = @import("options");
const engine = @import("engine");
const testkit = @import("testkit");

test "find equals the Python oracle on every golden query" {
    if (options.skills_src.len == 0) return error.SkillsSourceNotGiven;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;
    const golden = try std.Io.Dir.cwd().readFileAlloc(io, "data/golden/find-symptoms.tsv", arena, .limited(1 << 20));
    var cur_query: []const u8 = "";
    var rows: []const engine.FindRow = &.{};
    const tree = try std.fmt.allocPrint(arena, "{s}/skills", .{options.skills_src});
    var e = try engine.Engine.initTree(arena, io, try testkit.env(arena, &.{ .{ "SPARKY_STEREO_PACKAGES", "x" }, .{ "HOME", "/tmp" } }), "developer", tree, null);
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, golden, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var f = std.mem.splitScalar(u8, line, '\t');
        const query = f.next().?;
        const want_rank = try std.fmt.parseInt(usize, f.next().?, 10);
        const want_name = f.next().?;
        const want_score = try std.fmt.parseFloat(f64, f.next().?);
        if (!std.mem.eql(u8, query, cur_query)) {
            cur_query = query;
            rows = try e.find(query, 3, true);
        }
        try std.testing.expect(want_rank <= rows.len);
        const got = rows[want_rank - 1];
        try std.testing.expectEqualStrings(want_name, got.name);
        try std.testing.expectApproxEqAbs(want_score, got.score, 0.005);
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 33), checked);
}
