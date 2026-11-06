//! Tool: one file of one skill, for assistants that show only tools.
const std = @import("std");
const engine = @import("engine");
const jsonargs = @import("jsonargs");

pub const name = "skills_read";
pub const description = "Read one file of one skill (at most 256 KiB), by skill name and relative file, or by its skill:// address.";
pub const input_schema =
    \\{"type":"object","properties":{"uri":{"type":"string"},"skill":{"type":"string"},"file":{"type":"string","default":"SKILL.md"}},"additionalProperties":false}
;
pub const read_only = true;

pub fn call(e: *engine.Engine, args: std.json.Value) anyerror![]const u8 {
    const o = try jsonargs.object(args);
    if (try jsonargs.string(o, "uri")) |u| {
        const p = try engine.parseUri(u);
        const origin: engine.Origin = std.meta.stringToEnum(engine.Origin, p.origin) orelse return error.InvalidArgument;
        return e.read(p.name, origin, p.file);
    }
    return e.read(try jsonargs.requiredString(o, "skill"), null, (try jsonargs.string(o, "file")) orelse "SKILL.md");
}
