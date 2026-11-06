//! L5 operation: the skills a person or assistant may be told about: the installed ones (all of them with `all`).
const std = @import("std");
const skill_record = @import("skill_record");

pub fn run(arena: std.mem.Allocator, recs: []const skill_record.Rec, kind: ?[]const u8, all: bool) ![]const skill_record.Rec {
    var out: std.ArrayList(skill_record.Rec) = .empty;
    for (recs) |r| {
        if (!all and !r.eligible) continue;
        if (kind) |k| if (!std.mem.eql(u8, k, r.kind)) continue;
        try out.append(arena, r);
    }
    return out.items;
}
