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

fn contains(list: []const []const u8, name: []const u8) bool {
    for (list) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

/// Ids of the assistants found, in the order of `assistants`; empty means none.
pub fn found(arena: std.mem.Allocator, assistants: []const Assistant, probe: Probe) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (assistants) |a| {
        var hit = false;
        for (a.programs) |p| if (contains(probe.on_path, p)) {
            hit = true;
        };
        for (a.home_dirs) |h| if (contains(probe.in_home, h)) {
            hit = true;
        };
        if (hit) try out.append(arena, a.id);
    }
    return out.toOwnedSlice(arena);
}
