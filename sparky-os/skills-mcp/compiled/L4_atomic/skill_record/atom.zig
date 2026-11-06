//! L4 atom: what the engine knows about one skill. Plain data, no behaviour.
const std = @import("std");

pub const Origin = enum { system, user };

pub const Rec = struct {
    name: []const u8,
    /// The folder under `agent-skills/` that holds it: a skill kind's `folder`.
    kind: []const u8,
    origin: Origin,
    /// Absolute path of the skill's folder.
    dir: []const u8,
    description: []const u8,
    requires_packages: []const u8,
    /// The task-table text from the skills index for this skill; empty outside a checkout.
    task_rows: []const u8,
    /// Installed, by `requires-packages` (always true when the field is empty).
    eligible: bool,
};

pub fn skillFile(arena: std.mem.Allocator, r: Rec) ![]u8 {
    return std.fmt.allocPrint(arena, "{s}/SKILL.md", .{r.dir});
}
