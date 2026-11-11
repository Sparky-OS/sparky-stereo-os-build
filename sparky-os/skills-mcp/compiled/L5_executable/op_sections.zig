//! L5 operation: the exact headings of a skill, for `context` to select from.
const std = @import("std");
const fsio = @import("fsio");
const sections = @import("sections");
const skill_record = @import("skill_record");

pub fn run(arena: std.mem.Allocator, io: std.Io, rec: skill_record.Rec) ![]const sections.Heading {
    const path = try skill_record.skillFile(arena, rec);
    const text = try fsio.readFile(arena, io, path, 4 << 20);
    return sections.headings(arena, text);
}
