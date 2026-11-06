//! Lower levels never depend on higher ones, and the tree keeps its mirror.
//! Rank (bottom up): L6 primitive 0, L4 atomic 1, L5 executable 2, L3 organization 3, L2 context 4, L1 domain 5.
//! A file may import only names of strictly lower rank (its own atom's siblings are not importable at all),
//! `std`, and the build-given `options`. `surfaces/` may import L1 domain and L6 primitives only.
const std = @import("std");

const Level = struct { dir: []const u8, rank: u8 };
const levels = [_]Level{
    .{ .dir = "compiled/L6_primitive", .rank = 0 },
    .{ .dir = "compiled/L4_atomic", .rank = 1 },
    .{ .dir = "compiled/L5_executable", .rank = 2 },
    .{ .dir = "compiled/L3_organization", .rank = 3 },
    .{ .dir = "compiled/L2_context", .rank = 4 },
    .{ .dir = "compiled/L1_domain", .rank = 5 },
};
const surfaces_rank: u8 = 6;

/// Rank of an imported module name: primitives are named by file stem, atoms by folder, operations by stem.
fn rankOfImport(gpa: std.mem.Allocator, io: std.Io, name: []const u8) !?u8 {
    inline for (.{ .{ "compiled/L6_primitive", 0 }, .{ "compiled/L5_executable", 2 } }) |p| {
        const path = try std.fmt.allocPrint(gpa, "{s}/{s}.zig", .{ p[0], name });
        defer gpa.free(path);
        if (std.Io.Dir.cwd().access(io, path, .{})) |_| return p[1] else |_| {}
    }
    const apath = try std.fmt.allocPrint(gpa, "compiled/L4_atomic/{s}/atom.zig", .{name});
    defer gpa.free(apath);
    if (std.Io.Dir.cwd().access(io, apath, .{})) |_| return 1 else |_| {}
    return null;
}

fn importsOf(gpa: std.mem.Allocator, src: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    const needle = "@import(\"";
    while (std.mem.indexOfPos(u8, src, i, needle)) |at| {
        const start = at + needle.len;
        const end = std.mem.indexOfScalarPos(u8, src, start, '"') orelse break;
        try out.append(gpa, src[start..end]);
        i = end;
    }
    return out.toOwnedSlice(gpa);
}

test "no file under compiled/ imports a module of equal or higher rank, or a file path" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const gpa = arena_state.allocator();
    const io = std.testing.io;
    var checked: usize = 0;
    for (levels) |lv| {
        var dir = std.Io.Dir.cwd().openDir(io, lv.dir, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var walker = try dir.walk(gpa);
        defer walker.deinit();
        while (try walker.next(io)) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.path, ".zig")) continue;
            if (std.mem.indexOf(u8, e.path, "_kinds") != null) continue;
            const src = try dir.readFileAlloc(io, e.path, gpa, .limited(1 << 20));
            for (try importsOf(gpa, src)) |imp| {
                if (std.mem.eql(u8, imp, "std") or std.mem.eql(u8, imp, "options")) continue;
                if (std.mem.endsWith(u8, imp, ".zig")) {
                    std.debug.print("{s}/{s}: imports a file path ({s}); import a named module\n", .{ lv.dir, e.path, imp });
                    return error.FilePathImport;
                }
                const r = (try rankOfImport(gpa, io, imp)) orelse {
                    std.debug.print("{s}/{s}: imports unknown module {s}\n", .{ lv.dir, e.path, imp });
                    return error.UnknownImport;
                };
                if (r >= lv.rank) {
                    std.debug.print("{s}/{s}: rank {d} imports {s} of rank {d}\n", .{ lv.dir, e.path, lv.rank, imp, r });
                    return error.UpwardImport;
                }
                checked += 1;
            }
        }
    }
    // L1 domain, L2 context and L3 organization are empty at 2a; the first import checks arrive with the first operations.
    try std.testing.expect(checked > 0);
}

test "surfaces import only the domain facade and primitives" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const gpa = arena_state.allocator();
    const io = std.testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, "surfaces", .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    var files: usize = 0;
    while (try walker.next(io)) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.path, ".zig")) continue;
        files += 1;
        const src = try dir.readFileAlloc(io, e.path, gpa, .limited(1 << 20));
        for (try importsOf(gpa, src)) |imp| {
            if (std.mem.eql(u8, imp, "std") or std.mem.eql(u8, imp, "options") or std.mem.eql(u8, imp, "engine")) continue;
            const r = (try rankOfImport(gpa, io, imp)) orelse return error.UnknownImport;
            if (r != 0) {
                std.debug.print("surfaces/{s}: imports {s} (rank {d}); only engine and primitives are allowed\n", .{ e.path, imp, r });
                return error.SurfaceReachesInside;
            }
        }
    }
    try std.testing.expect(files > 0);
    _ = surfaces_rank;
}

test "every level folder under compiled/ has its mirror under tests/ and a _topic_summary.md" {
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    for (levels) |lv| {
        const name = lv.dir["compiled/".len..];
        var buf: [128]u8 = undefined;
        const mirror = try std.fmt.bufPrint(&buf, "tests/{s}", .{name});
        cwd.access(io, mirror, .{}) catch {
            std.debug.print("missing mirror folder {s}\n", .{mirror});
            return error.HalfMirror;
        };
        var sbuf: [160]u8 = undefined;
        const summary = try std.fmt.bufPrint(&sbuf, "{s}/_topic_summary.md", .{lv.dir});
        cwd.access(io, summary, .{}) catch {
            std.debug.print("missing {s}\n", .{summary});
            return error.NoTopicSummary;
        };
    }
}
