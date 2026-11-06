//! Tool: the commands a user skill lists, and who approves each.
const std = @import("std");
const engine = @import("engine");
const jsonargs = @import("jsonargs");

pub const name = "skills_commands";
pub const description = "List the commands a user skill lists in its commands.json. Only these can ever run, through skills_run, and only as the person's command policy allows.";
pub const input_schema =
    \\{"type":"object","properties":{"skill":{"type":"string"}},"required":["skill"],"additionalProperties":false}
;
pub const read_only = true;

pub fn call(e: *engine.Engine, args: std.json.Value) anyerror![]const u8 {
    const o = try jsonargs.object(args);
    const skill = try jsonargs.requiredString(o, "skill");
    const cmds = try e.commands(skill);
    var out: std.ArrayList(u8) = .empty;
    if (cmds.len == 0) return "This skill lists no commands.";
    for (cmds) |c| {
        const g = try e.gate(skill, c.id, .mcp);
        const who = switch (g.decision) {
            .run_assistant_approves => "may be run through skills_run (the assistant's own approval applies)",
            .ask_person => "needs the person to run it: ask them to run exactly the line below",
            .refuse => |why| why,
        };
        try out.print(e.arena, "{s}: {s}\n  command:", .{ c.id, who });
        for (c.argv) |a| try out.print(e.arena, " {s}", .{a});
        try out.print(e.arena, "\n  by hand: sparky-stereo-skills run {s} {s}", .{ skill, c.id });
        for (c.slots) |s| try out.print(e.arena, " {s}=<{s}>", .{ s.name, s.class });
        try out.append(e.arena, '\n');
    }
    return out.items;
}
