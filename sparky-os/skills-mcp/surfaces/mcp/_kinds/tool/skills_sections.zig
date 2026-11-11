//! Tool: the exact headings of a skill.
const std = @import("std");
const engine = @import("engine");
const jsonargs = @import("jsonargs");

pub const name = "skills_sections";
pub const description = "List the exact headings of one skill, so skills_context can read just one section.";
pub const input_schema =
    \\{"type":"object","properties":{"skill":{"type":"string"}},"required":["skill"],"additionalProperties":false}
;
pub const read_only = true;

pub fn call(e: *engine.Engine, args: std.json.Value) anyerror![]const u8 {
    const o = try jsonargs.object(args);
    var out: std.ArrayList(u8) = .empty;
    for (try e.sectionsOf(try jsonargs.requiredString(o, "skill"))) |h| try out.print(e.arena, "{s}\n", .{h.title});
    return out.items;
}
