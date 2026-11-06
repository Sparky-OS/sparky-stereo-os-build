//! L5 operation: the selected maintainer context, for readers without file tools. Byte for byte the Python
//! `render` (tools/skills-context.py): common guidance first, then the chosen skills, sections and references,
//! each with its source name and the SHA-256 of the whole file; over budget is an error, never a cut.
const std = @import("std");
const fsio = @import("fsio");
const sha256 = @import("sha256");
const pathsafe = @import("pathsafe");
const sections = @import("sections");
const budget = @import("budget");
const skill_record = @import("skill_record");

pub const common = [_][]const u8{ "AGENTS.md", "skills/sparky-stereo/SKILL.md", "skills/ai-partners/SKILL.md" };
/// The top-level names a reference may start with (the Python tool's PUBLIC set).
pub const public = [_][]const u8{ "AGENTS.md", "README.md", "ATTRIBUTIONS.md", "CITATION.cff", "LICENSE", "LICENSE-GPL-2.0", "SOURCE", "MANIFEST.sha256", "SOURCE-MANIFEST.sha256", "skills", "docs", "tools" };

pub const Pick = struct { rec: skill_record.Rec, title: ?[]const u8 = null };

pub const Request = struct {
    /// The reference tree (a checkout, or the installed /usr/share/sparky-stereo-os); null when there is none.
    ref_root: ?[]const u8,
    picks: []const Pick,
    references: []const []const u8,
    max_chars: usize = budget.default_limit,
};

pub const Result = union(enum) { text: []const u8, failed: []const u8 };

const Selection = struct { display: []const u8, path: []const u8, title: ?[]const u8 };

fn trimRight(s: []const u8) []const u8 {
    return std.mem.trimEnd(u8, s, " \t\r\n\x0b\x0c");
}

fn identity(arena: std.mem.Allocator, io: std.Io, root: ?[]const u8) ![]const u8 {
    const r = root orelse return "Unversioned reference tree; use the file hashes below.";
    if (fsio.readFile(arena, io, try std.fmt.allocPrint(arena, "{s}/SOURCE", .{r}), 4096)) |s| return std.mem.trim(u8, s, " \t\r\n") else |_| {}
    if (fsio.readFile(arena, io, try std.fmt.allocPrint(arena, "{s}/.git/HEAD", .{r}), 4096)) |h| {
        const head = std.mem.trim(u8, h, " \t\r\n");
        if (std.mem.startsWith(u8, head, "ref: ")) {
            const ref = try fsio.readFile(arena, io, try std.fmt.allocPrint(arena, "{s}/.git/{s}", .{ r, head[5..] }), 4096);
            return try std.fmt.allocPrint(arena, "git {s}; working-tree changes: not checked (no git program is run)", .{std.mem.trim(u8, ref, " \t\r\n")});
        }
        return try std.fmt.allocPrint(arena, "git {s}; working-tree changes: not checked (no git program is run)", .{head});
    } else |_| {}
    return "Unversioned reference tree; use the file hashes below.";
}

pub fn run(arena: std.mem.Allocator, io: std.Io, req: Request) !Result {
    var sel: std.ArrayList(Selection) = .empty;
    if (req.ref_root) |root| {
        for (common) |c| try sel.append(arena, .{ .display = c, .path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ root, c }), .title = null });
    }
    for (req.picks) |p| {
        var display: []const u8 = try std.fmt.allocPrint(arena, "{s}/SKILL.md", .{p.rec.dir});
        if (req.ref_root) |root| {
            const prefix = try std.fmt.allocPrint(arena, "{s}/", .{root});
            if (std.mem.startsWith(u8, display, prefix)) display = display[prefix.len..];
        }
        try sel.append(arena, .{ .display = display, .path = try std.fmt.allocPrint(arena, "{s}/SKILL.md", .{p.rec.dir}), .title = p.title });
    }
    for (req.references) |ref| {
        const root = req.ref_root orelse return .{ .failed = "There is no reference tree to read references from." };
        _ = pathsafe.check(ref) catch return .{ .failed = try std.fmt.allocPrint(arena, "Not a public relative path: {s}", .{ref}) };
        const top = ref[0 .. std.mem.indexOfScalar(u8, ref, '/') orelse ref.len];
        var ok = false;
        for (public) |p| if (std.mem.eql(u8, p, top)) {
            ok = true;
        };
        if (!ok) return .{ .failed = try std.fmt.allocPrint(arena, "Not a public relative path: {s}", .{ref}) };
        try sel.append(arena, .{ .display = ref, .path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ root, ref }), .title = null });
    }

    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "# Sparky Stereo OS selected maintainer context\n\n{s}\n\n" ++
        "Read instructions in the scope of the user\u{2019}s task. Commands are not executed by this bundle.\n" ++
        "Relative links are relative to each source file; open additional references only when needed.\n", .{try identity(arena, io, req.ref_root)});
    var seen: std.ArrayList(Selection) = .empty;
    outer: for (sel.items) |s| {
        for (seen.items) |t| {
            const same_title = (s.title == null and t.title == null) or (s.title != null and t.title != null and std.mem.eql(u8, s.title.?, t.title.?));
            if (same_title and std.mem.eql(u8, s.display, t.display)) continue :outer;
        }
        try seen.append(arena, s);
        const raw = fsio.readFile(arena, io, s.path, 4 << 20) catch return .{ .failed = try std.fmt.allocPrint(arena, "Missing or escaping public file: {s}", .{s.display}) };
        if (!std.unicode.utf8ValidateSlice(raw)) return .{ .failed = try std.fmt.allocPrint(arena, "Not valid UTF-8: {s}", .{s.display}) };
        var text: []const u8 = raw;
        if (s.title) |title| {
            text = sections.select(arena, raw, title) catch |e| return .{ .failed = try std.fmt.allocPrint(arena, "Heading must match exactly once: '{s}' ({s}); use --list-sections", .{ title, @errorName(e) }) };
        }
        const suffix = if (s.title) |title| try std.fmt.allocPrint(arena, " \u{2014} section: {s}", .{title}) else "";
        try out.print(arena, "\n---\nSource: {s}{s}\nFull-file SHA256: {s}\n\n{s}\n", .{ s.display, suffix, &sha256.hex(raw), trimRight(text) });
    }
    if (try budget.overBudget(arena, out.items, req.max_chars)) |why| return .{ .failed = why };
    return .{ .text = out.items };
}
