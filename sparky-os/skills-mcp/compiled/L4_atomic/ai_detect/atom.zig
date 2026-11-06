//! L4 atom: does the person already use an AI assistant. The answer names which, so the person can see why.
const std = @import("std");

pub const Probe = struct {
    /// Programs found on PATH (names only).
    on_path: []const []const u8,
    /// Paths found under the person's home (relative, such as ".claude" or ".codex").
    in_home: []const []const u8,
};

pub const Assistant = struct {
    id: []const u8,
    programs: []const []const u8,
    home_dirs: []const []const u8,
};

/// Ids of the assistants found, in the order of `assistants`; empty means none.
pub fn found(arena: std.mem.Allocator, assistants: []const Assistant, probe: Probe) ![]const []const u8 {
    _ = arena;
    _ = assistants;
    _ = probe;
    return error.NotImplemented;
}
