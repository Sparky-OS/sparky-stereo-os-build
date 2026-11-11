//! The ranking arithmetic on a three-skill world small enough to compute by hand.
//! weight(t) = ln(1 + (N - n + 0.5) / (n + 0.5)), N skills, n of them having the term; field weights name 3, task table 2, description 1.
const std = @import("std");
const rank = @import("rank");

const world = [_]rank.Skill{
    .{ .name = "audio", .description = "PipeWire and the Sound page", .task_rows = "no sound after login" },
    .{ .name = "drivers", .description = "kernel and GPU drivers, HDMI modes", .task_rows = "" },
    .{ .name = "lean-code", .description = "text files without comments", .task_rows = "" },
};

test "the only skill that has the term ranks first, with the hand computed score" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const rows = try rank.rank(arena.allocator(), &world, "pipewire", 3);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqualStrings("audio", rows[0].name);
    // N = 3, n = 1: ln(1 + 2.5 / 1.5) = ln(8/3); the term is in the description only: weight 1.0
    try std.testing.expectApproxEqAbs(@log(8.0 / 3.0), rows[0].score, 1e-6);
}

test "no matching term gives no rows, and the limit is honoured" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), (try rank.rank(arena.allocator(), &world, "zzzz", 3)).len);
    const rows = try rank.rank(arena.allocator(), &world, "files drivers", 1);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
}
