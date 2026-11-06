//! L5 operation: rank the installed skills for a task or symptom. Same answer as the Python `--find`.
const std = @import("std");
const rank = @import("rank");

pub const Row = struct {
    rank: usize,
    name: []const u8,
    score: f64,
    description: []const u8,
};

/// `root` is a checkout of the public tree: `root/skills/<name>/SKILL.md` and the task table in `root/skills/README.md`.
pub fn run(arena: std.mem.Allocator, io: std.Io, root: []const u8, query: []const u8, limit: usize) ![]const Row {
    _ = arena;
    _ = io;
    _ = root;
    _ = query;
    _ = limit;
    return error.NotImplemented;
}
