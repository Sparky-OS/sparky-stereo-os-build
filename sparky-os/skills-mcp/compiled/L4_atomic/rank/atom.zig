//! L4 atom: the offline, deterministic ranking of skills for a task or symptom, equal to the Python `find`.
const std = @import("std");

pub const Skill = struct {
    name: []const u8,
    description: []const u8,
    /// The skills index's task-table text for this skill; empty when none.
    task_rows: []const u8,
};

pub const Row = struct { name: []const u8, score: f64 };

/// Rows with a score above zero, best first, ties by name, at most `limit`.
pub fn rank(arena: std.mem.Allocator, skills: []const Skill, query: []const u8, limit: usize) ![]const Row {
    _ = arena;
    _ = skills;
    _ = query;
    _ = limit;
    return error.NotImplemented;
}
