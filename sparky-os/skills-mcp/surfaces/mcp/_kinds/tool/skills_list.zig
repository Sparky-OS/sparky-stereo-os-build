//! Tool: list the skills this system serves.
const std = @import("std");
const engine = @import("engine");
const jsonargs = @import("jsonargs");

pub const name = "skills_list";
pub const description = "List the installed skills: name, kind, origin and description. Skills whose package is not installed are not listed unless all is true.";
pub const input_schema =
    \\{"type":"object","properties":{"kind":{"type":"string","description":"Only skills of this kind"},"all":{"type":"boolean","default":false}},"additionalProperties":false}
;
pub const read_only = true;

pub fn call(e: *engine.Engine, args: std.json.Value) anyerror![]const u8 {
    const o = try jsonargs.object(args);
    const recs = try e.list(try jsonargs.string(o, "kind"), (try jsonargs.boolean(o, "all")) orelse false);
    var out: std.ArrayList(u8) = .empty;
    for (recs) |r| try out.print(e.arena, "{s}\t{s}\t{s}\t{s}\n", .{ r.name, r.kind, @tagName(r.origin), r.description });
    if (recs.len == 0) return "No skill is installed for that request.";
    return out.items;
}
