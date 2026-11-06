//! Tool: run one command that a user skill lists. Never a command that is not listed; the gate decides who approves.
const std = @import("std");
const engine = @import("engine");
const jsonargs = @import("jsonargs");

pub const name = "skills_run";
pub const description = "Run one command that a user skill lists (see skills_commands). Slots are filled from values, never from free text. If the person's policy needs their confirmation, the call is refused with the line for them to run.";
pub const input_schema =
    \\{"type":"object","properties":{"skill":{"type":"string"},"id":{"type":"string"},"values":{"type":"object","additionalProperties":{"type":"string"}}},"required":["skill","id"],"additionalProperties":false}
;
pub const read_only = false;

pub fn call(e: *engine.Engine, args: std.json.Value) anyerror![]const u8 {
    const o = try jsonargs.object(args);
    const skill = try jsonargs.requiredString(o, "skill");
    const id = try jsonargs.requiredString(o, "id");
    const g = try e.gate(skill, id, .mcp);
    switch (g.decision) {
        .refuse => |why| {
            e.message = why;
            return error.Failed;
        },
        .ask_person => {
            e.message = try std.fmt.allocPrint(e.arena, "This command needs the person's confirmation, and this connection cannot ask them, so it was not run. Ask the person to run: sparky-stereo-skills run {s} {s}", .{ skill, id });
            return error.Failed;
        },
        .run_assistant_approves => {},
    }
    var values: std.ArrayList(engine.RunValue) = .empty;
    if (o.get("values")) |v| switch (v) {
        .object => |vo| {
            var it = vo.iterator();
            while (it.next()) |kv| switch (kv.value_ptr.*) {
                .string => |s| try values.append(e.arena, .{ .name = kv.key_ptr.*, .value = s }),
                else => return error.InvalidArgument,
            };
        },
        .null => {},
        else => return error.InvalidArgument,
    };
    const r = try e.runApproved(skill, id, values.items);
    var out: std.ArrayList(u8) = .empty;
    try out.print(e.arena, "exit: {?d}{s}\nexpected result: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ r.exit_code, if (r.timed_out) " (timed out)" else "", if (r.expected) "matched" else "NOT matched", r.stdout, r.stderr });
    return out.items;
}
