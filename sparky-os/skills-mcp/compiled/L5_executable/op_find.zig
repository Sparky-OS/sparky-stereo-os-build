//! L5 operation: rank the installed skills for a task or symptom. Same answer as the Python `--find`.
const std = @import("std");
const rank = @import("rank");
const skill_record = @import("skill_record");

pub const Row = struct {
    rank: usize,
    name: []const u8,
    score: f64,
    description: []const u8,
    kind: []const u8,
    origin: skill_record.Origin,
    dir: []const u8,
};

/// Eligible skills only, unless `all`. Two skills with one name are both ranked, each with its own origin.
pub fn run(arena: std.mem.Allocator, recs: []const skill_record.Rec, query: []const u8, limit: usize, all: bool) ![]const Row {
    var pool: std.ArrayList(rank.Skill) = .empty;
    var index: std.ArrayList(usize) = .empty;
    for (recs, 0..) |r, i| {
        if (!all and !r.eligible) continue;
        try pool.append(arena, .{ .name = r.name, .description = r.description, .task_rows = r.task_rows });
        try index.append(arena, i);
    }
    // The ranking is by name; pair rows back to records in order for duplicate names.
    const ranked = try rank.rank(arena, pool.items, query, pool.items.len);
    var out: std.ArrayList(Row) = .empty;
    var used = try arena.alloc(bool, pool.items.len);
    @memset(used, false);
    for (ranked) |rw| {
        if (out.items.len >= limit) break;
        for (pool.items, 0..) |p, k| {
            if (used[k] or !std.mem.eql(u8, p.name, rw.name)) continue;
            used[k] = true;
            const r = recs[index.items[k]];
            try out.append(arena, .{ .rank = out.items.len + 1, .name = r.name, .score = rw.score, .description = try oneLine(arena, r.description), .kind = r.kind, .origin = r.origin, .dir = r.dir });
            break;
        }
    }
    return out.items;
}

/// `" ".join(desc.split())`.
fn oneLine(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, s, " \t\r\n");
    while (it.next()) |w| {
        if (out.items.len > 0) try out.append(arena, ' ');
        try out.appendSlice(arena, w);
    }
    return out.items;
}
