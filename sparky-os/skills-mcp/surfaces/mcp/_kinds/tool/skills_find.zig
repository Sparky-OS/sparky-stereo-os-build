//! Tool: rank the installed skills for a task or symptom. Same answer as `sparky-stereo-skills find`.
const std = @import("std");
const engine = @import("engine");
const jsonargs = @import("jsonargs");

pub const name = "skills_find";
pub const description = "Find the skills that answer a task or symptom, in plain words. Ranked offline by name, description and the task table; only installed skills are listed. Call this first, then skills_context with the name.";
pub const input_schema =
    \\{"type":"object","properties":{"query":{"type":"string","description":"The task or symptom, in a few words"},"limit":{"type":"integer","minimum":1,"maximum":10,"default":3},"all":{"type":"boolean","default":false,"description":"Also rank skills whose package is not installed"}},"required":["query"],"additionalProperties":false}
;
pub const read_only = true;

pub fn call(e: *engine.Engine, args: std.json.Value) anyerror![]const u8 {
    const o = try jsonargs.object(args);
    const q = try jsonargs.requiredString(o, "query");
    const limit: usize = @intCast((try jsonargs.int(o, "limit")) orelse 3);
    const rows = try e.find(q, limit, (try jsonargs.boolean(o, "all")) orelse false);
    var out: std.ArrayList(u8) = .empty;
    if (rows.len == 0) return "No skill matches those words. Try skills_list to see every installed skill.";
    try out.print(e.arena, "ranker: offline (name, description, task table)\n", .{});
    for (rows) |r| {
        try out.print(e.arena, "{d}. {s} (score {d:.2}, {s}, {s})\n   {s}\n   {s}\n   Next: skills_context with skills [\"{s}\"]\n", .{ r.rank, r.name, r.score, @tagName(r.origin), r.kind, r.description, try e.uriOf(r.name, r.kind, r.origin, "SKILL.md"), r.name });
    }
    return out.items;
}
