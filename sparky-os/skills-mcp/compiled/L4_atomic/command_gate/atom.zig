//! L4 atom: may a command of a user skill run now, and who must say yes.
//! The rule: a person with no AI assistant on the system confirms every command first; a person who already uses
//! AI assistants gets the commands by default, under that assistant's own approval. Both are choices the person can change.
//! Through the command line the person is the one at the keyboard, so the person is always asked: no assistant is in the loop.
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
    if (!listed) return .{ .refuse = "That command is not listed by the skill, so it was not run." };
    if (via == .cli or marked == .person) return .ask_person;
    return switch (policy) {
        .ask => .ask_person,
        .assistant => .run_assistant_approves,
        .auto => if (ai_tool_found) .run_assistant_approves else .ask_person,
    };
}

pub fn parsePolicy(text: []const u8) ?Policy {
    return std.meta.stringToEnum(Policy, text);
}
