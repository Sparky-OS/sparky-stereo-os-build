//! L5 operation: the complete manifest of one skill, as the Skills extension lists it: every file's URI, digest and size.
//! At most 512 files and 16 MiB; a skill over either limit is refused with the reason, not served in part.
const std = @import("std");
const fsio = @import("fsio");
const manifest = @import("manifest");
const skill_record = @import("skill_record");
const skill_uri = @import("skill_uri");

pub const max_files: usize = 512;
pub const max_total: usize = 16 * 1024 * 1024;

pub const Error = anyerror;

pub fn run(arena: std.mem.Allocator, io: std.Io, rec: skill_record.Rec) Error![]const manifest.Entry {
    var out: std.ArrayList(manifest.Entry) = .empty;
    var total: usize = 0;
    try walk(arena, io, rec, "", &out, &total);
    std.mem.sort(manifest.Entry, out.items, {}, struct {
        fn lt(_: void, a: manifest.Entry, b: manifest.Entry) bool {
            return std.mem.lessThan(u8, a.uri, b.uri);
        }
    }.lt);
    return out.items;
}

fn walk(arena: std.mem.Allocator, io: std.Io, rec: skill_record.Rec, rel: []const u8, out: *std.ArrayList(manifest.Entry), total: *usize) Error!void {
    const dir = if (rel.len == 0) rec.dir else try std.fmt.allocPrint(arena, "{s}/{s}", .{ rec.dir, rel });
    for (try fsio.listDir(arena, io, dir)) |e| {
        const child = if (rel.len == 0) e.name else try std.fmt.allocPrint(arena, "{s}/{s}", .{ rel, e.name });
        switch (e.kind) {
            .directory => try walk(arena, io, rec, child, out, total),
            .file => {
                if (out.items.len >= max_files) return error.TooManyFiles;
                const bytes = fsio.readFile(arena, io, try std.fmt.allocPrint(arena, "{s}/{s}", .{ rec.dir, child }), max_total) catch |err| switch (err) {
                    error.StreamTooLong => return error.TooLarge,
                    else => |o| return o,
                };
                total.* += bytes.len;
                if (total.* > max_total) return error.TooLarge;
                const uri = try skill_uri.format(arena, @tagName(rec.origin), rec.kind, rec.name, child);
                try out.append(arena, try manifest.entry(uri, bytes));
            },
            .other => {},
        }
    }
}
