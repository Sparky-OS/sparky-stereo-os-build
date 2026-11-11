//! Tool: the selected context of skills, sections and references; the same text as `sparky-stereo-skills context`.
const std = @import("std");
const engine = @import("engine");
const jsonargs = @import("jsonargs");

pub const name = "skills_context";
pub const description = "Return the text of skills (and optionally one section of a skill, or a reference file) with the common guidance and each file's SHA-256. Commands in the text are not executed. Over the character budget it fails and nothing is cut.";
pub const input_schema =
    \\{"type":"object","properties":{"skills":{"type":"array","items":{"type":"string"}},"sections":{"type":"array","items":{"type":"string"},"description":"skill-name:Exact heading"},"references":{"type":"array","items":{"type":"string"},"description":"A public relative path such as docs/glossary.md"},"max_chars":{"type":"integer","minimum":1,"default":48000}},"additionalProperties":false}
;
pub const read_only = true;

pub fn call(e: *engine.Engine, args: std.json.Value) anyerror![]const u8 {
    const o = try jsonargs.object(args);
    const max = (try jsonargs.int(o, "max_chars")) orelse 48000;
    if (max <= 0) return error.InvalidArgument;
    return e.context(.{
        .names = try jsonargs.strings(e.arena, o, "skills"),
        .sections = try jsonargs.strings(e.arena, o, "sections"),
        .references = try jsonargs.strings(e.arena, o, "references"),
        .max_chars = @intCast(max),
    });
}
