//! Commands in skills run with the person's confirmation when no AI assistant is on the system, and by default under the
//! assistant's own approval when one is. Both ways, and every refusal, so no cell of the table is untested.
const std = @import("std");
const gate = @import("command_gate");

const D = gate.Decision;

test "auto with an AI tool found: the assistant's own approval applies" {
    try std.testing.expectEqual(D.run_assistant_approves, gate.decide(.auto, true, true, .assistant, .mcp));
}

test "auto with no AI tool: the person confirms first, whichever door" {
    try std.testing.expectEqual(D.ask_person, gate.decide(.auto, false, true, .assistant, .cli));
    try std.testing.expectEqual(D.ask_person, gate.decide(.auto, false, true, .assistant, .mcp));
}

test "a command marked person always asks the person, even with an AI tool" {
    try std.testing.expectEqual(D.ask_person, gate.decide(.auto, true, true, .person, .mcp));
    try std.testing.expectEqual(D.ask_person, gate.decide(.assistant, true, true, .person, .mcp));
}

test "policy ask forces the question even with an AI tool" {
    try std.testing.expectEqual(D.ask_person, gate.decide(.ask, true, true, .assistant, .mcp));
}

test "policy assistant lets the assistant approve even when none was found" {
    try std.testing.expectEqual(D.run_assistant_approves, gate.decide(.assistant, false, true, .assistant, .mcp));
}

test "a command the skill does not list is refused in every combination, with a reason" {
    for ([_]gate.Policy{ .auto, .assistant, .ask }) |p| for ([_]bool{ true, false }) |ai| for ([_]gate.Via{ .mcp, .cli }) |v| {
        switch (gate.decide(p, ai, false, .assistant, v)) {
            .refuse => |why| try std.testing.expect(why.len > 0),
            else => return error.TestUnexpectedResult,
        }
    };
}
