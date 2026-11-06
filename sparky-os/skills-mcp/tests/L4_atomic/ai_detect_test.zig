//! How the server knows the person already uses AI tools: an assistant it registers with is on PATH or has its
//! configuration folder in the person's home. The answer names the assistants found.
const std = @import("std");
const ai_detect = @import("ai_detect");

const assistants = [_]ai_detect.Assistant{
    .{ .id = "claude_code", .programs = &.{"claude"}, .home_dirs = &.{".claude"} },
    .{ .id = "codex", .programs = &.{"codex"}, .home_dirs = &.{".codex"} },
};

test "nothing found means none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try ai_detect.found(arena.allocator(), &assistants, .{ .on_path = &.{ "bash", "ls" }, .in_home = &.{".config"} });
    try std.testing.expectEqual(@as(usize, 0), got.len);
}

test "a program on PATH counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try ai_detect.found(arena.allocator(), &assistants, .{ .on_path = &.{"codex"}, .in_home = &.{} });
    try std.testing.expectEqual(@as(usize, 1), got.len);
    try std.testing.expectEqualStrings("codex", got[0]);
}

test "a configuration folder in the home counts, and order follows the assistant list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try ai_detect.found(arena.allocator(), &assistants, .{ .on_path = &.{"codex"}, .in_home = &.{".claude"} });
    try std.testing.expectEqual(@as(usize, 2), got.len);
    try std.testing.expectEqualStrings("claude_code", got[0]);
    try std.testing.expectEqualStrings("codex", got[1]);
}
