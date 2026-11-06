//! L3 organization: the one list of skills. Finds the trees to read (freedesktop data directories and the
//! `paths.d` files that name a tree that has to stay where it is), reads every skill in them and says which are installed.
//! Debian Policy 9.1.1 puts architecture-independent data in /usr/share; the freedesktop Base Directory
//! Specification 0.8 orders $XDG_DATA_HOME before each of $XDG_DATA_DIRS, a missing directory skipped.
const std = @import("std");
const fsio = @import("fsio");
const frontmatter = @import("frontmatter");
const eligibility = @import("eligibility");
const pathsafe = @import("pathsafe");
const skill_record = @import("skill_record");

pub const Tree = struct { origin: skill_record.Origin, kind: []const u8, path: []const u8 };

pub const Found = struct {
    trees: []const Tree,
    /// Plain sentences about things that were skipped, so nothing disappears silently.
    problems: []const []const u8,
};

pub const default_data_dirs = "/usr/local/share:/usr/share";

pub fn discover(arena: std.mem.Allocator, io: std.Io, xdg_home: []const u8, xdg_dirs: []const u8, known_kinds: []const []const u8) !Found {
    var trees: std.ArrayList(Tree) = .empty;
    var problems: std.ArrayList([]const u8) = .empty;
    var bases: std.ArrayList(struct { origin: skill_record.Origin, dir: []const u8 }) = .empty;
    if (xdg_home.len > 0) try bases.append(arena, .{ .origin = .user, .dir = xdg_home });
    var it = std.mem.splitScalar(u8, if (xdg_dirs.len == 0) default_data_dirs else xdg_dirs, ':');
    while (it.next()) |d| if (d.len > 0 and d[0] == '/') try bases.append(arena, .{ .origin = .system, .dir = d });
    for (bases.items) |b| {
        const root = try std.fmt.allocPrint(arena, "{s}/agent-skills", .{b.dir});
        const entries = fsio.listDir(arena, io, root) catch continue;
        for (entries) |e| {
            if (e.kind != .directory or std.mem.eql(u8, e.name, "paths.d")) continue;
            if (isKnown(known_kinds, e.name)) {
                try trees.append(arena, .{ .origin = b.origin, .kind = e.name, .path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ root, e.name }) });
            } else try problems.append(arena, try std.fmt.allocPrint(arena, "Unknown skill kind folder {s}/{s}; known kinds are not listed there, so it was not read.", .{ root, e.name }));
        }
        const pd = try std.fmt.allocPrint(arena, "{s}/paths.d", .{root});
        for (fsio.listDir(arena, io, pd) catch &.{}) |f| {
            if (!std.mem.endsWith(u8, f.name, ".conf")) continue;
            const text = fsio.readFile(arena, io, try std.fmt.allocPrint(arena, "{s}/{s}", .{ pd, f.name }), 64 * 1024) catch continue;
            var lines = std.mem.splitScalar(u8, text, '\n');
            while (lines.next()) |raw| {
                const line = std.mem.trim(u8, raw, " \t\r");
                if (line.len == 0 or line[0] == '#') continue;
                const sp = std.mem.indexOfAny(u8, line, " \t") orelse {
                    try problems.append(arena, try std.fmt.allocPrint(arena, "Bad line in {s}/{s}: {s}", .{ pd, f.name, line }));
                    continue;
                };
                const kind = line[0..sp];
                const path = std.mem.trim(u8, line[sp..], " \t");
                if (!isKnown(known_kinds, kind) or path.len == 0 or path[0] != '/') {
                    try problems.append(arena, try std.fmt.allocPrint(arena, "Bad line in {s}/{s}: {s}", .{ pd, f.name, line }));
                    continue;
                }
                try trees.append(arena, .{ .origin = b.origin, .kind = kind, .path = path });
            }
        }
    }
    return .{ .trees = trees.items, .problems = problems.items };
}

fn isKnown(kinds: []const []const u8, name: []const u8) bool {
    for (kinds) |k| if (std.mem.eql(u8, k, name)) return true;
    return false;
}

/// Every skill in `trees`, installed or not (`eligible` says which). A folder without SKILL.md, with a bad name, a name
/// that differs from the folder, or a broken front matter is skipped with a sentence in `problems`.
pub fn scan(arena: std.mem.Allocator, io: std.Io, trees: []const Tree, installed: eligibility.Installed, problems: *std.ArrayList([]const u8)) ![]const skill_record.Rec {
    var out: std.ArrayList(skill_record.Rec) = .empty;
    for (trees) |t| {
        const entries = fsio.listDir(arena, io, t.path) catch continue;
        const rows = readRows(arena, io, t.path) catch &.{};
        for (entries) |e| {
            if (e.kind != .directory) continue;
            const dir = try std.fmt.allocPrint(arena, "{s}/{s}", .{ t.path, e.name });
            const text = fsio.readFile(arena, io, try std.fmt.allocPrint(arena, "{s}/SKILL.md", .{dir}), 1 << 20) catch continue;
            if (!pathsafe.validName(e.name)) {
                try problems.append(arena, try std.fmt.allocPrint(arena, "{s} is not a valid skill name, so it was not served.", .{dir}));
                continue;
            }
            const fm = frontmatter.parse(arena, text) catch {
                try problems.append(arena, try std.fmt.allocPrint(arena, "{s}/SKILL.md has no readable front matter, so it was not served.", .{dir}));
                continue;
            };
            if (!std.mem.eql(u8, fm.name, e.name)) {
                try problems.append(arena, try std.fmt.allocPrint(arena, "{s}/SKILL.md names itself '{s}', which differs from its folder, so it was not served.", .{ dir, fm.name }));
                continue;
            }
            var task: []const u8 = "";
            for (rows) |r| if (std.mem.eql(u8, r.name, e.name)) {
                task = r.text;
            };
            try out.append(arena, .{
                .name = e.name,
                .kind = t.kind,
                .origin = t.origin,
                .dir = dir,
                .description = fm.description,
                .requires_packages = fm.requires_packages,
                .task_rows = task,
                .eligible = eligibility.allowed(fm.requires_packages, installed),
            });
        }
    }
    return out.items;
}

const Row = struct { name: []const u8, text: []const u8 };

/// The "Your task | Read next" table of a tree's README.md: each row's task text routes to the skills it links.
fn readRows(arena: std.mem.Allocator, io: std.Io, tree_path: []const u8) ![]const Row {
    const text = try fsio.readFile(arena, io, try std.fmt.allocPrint(arena, "{s}/README.md", .{tree_path}), 1 << 20);
    var rows: std.ArrayList(Row) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        line = std.mem.trim(u8, line, "|");
        var cells = std.mem.splitScalar(u8, line, '|');
        const c0 = std.mem.trim(u8, cells.next() orelse continue, " \t\r");
        const c1 = std.mem.trim(u8, cells.next() orelse continue, " \t\r");
        var only_dashes = true;
        for (c0) |ch| if (ch != '-' and ch != ':' and ch != ' ') {
            only_dashes = false;
        };
        if (only_dashes) continue;
        const marker = "/SKILL.md)";
        var from: usize = 0;
        while (std.mem.indexOfPos(u8, c1, from, marker)) |at| {
            from = at + marker.len;
            const open = std.mem.lastIndexOfScalar(u8, c1[0..at], '(') orelse continue;
            const name = c1[open + 1 .. at];
            if (!pathsafe.validName(name)) continue;
            // several rows may route to one skill: join their texts the way Python's ' '.join does
            var merged = false;
            for (rows.items) |*r| if (std.mem.eql(u8, r.name, name)) {
                r.text = try std.fmt.allocPrint(arena, "{s} {s}", .{ r.text, c0 });
                merged = true;
            };
            if (!merged) try rows.append(arena, .{ .name = name, .text = c0 });
        }
    }
    return rows.items;
}
