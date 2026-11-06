//! L4 atom: may a command of a user skill run now, and who must say yes (Daniel, 2026-11-06).
//! "with confirmation if the person has no ai tool, on by default if the user is already using AI tools".
const std = @import("std");

pub const Policy = enum { auto, assistant, ask };
pub const Marked = enum { assistant, person };
pub const Via = enum { mcp, cli };

pub const Decision = union(enum) {
    /// Run; the assistant's own approval applies.
    run_assistant_approves,
    /// Show the exact command and wait for the person's yes.
    ask_person,
    refuse: []const u8,
};

pub fn decide(policy: Policy, ai_tool_found: bool, listed: bool, marked: Marked, via: Via) Decision {
    _ = policy;
    _ = ai_tool_found;
    _ = listed;
    _ = marked;
    _ = via;
    return .{ .refuse = "not implemented" };
}
