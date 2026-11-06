//! L4 atom: the front matter of a SKILL.md (agentskills.io specification), only the fields the engine uses.
const std = @import("std");

pub const Frontmatter = struct {
    name: []const u8,
    description: []const u8,
    /// The raw `metadata: requires-packages:` text such as "monado-service | ffmpeg"; empty when absent.
    requires_packages: []const u8,
};

pub const Error = error{ InvalidArgument, OutOfMemory };

/// The block between the opening `---` line and the next `---` line, or null.
pub fn block(text: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, text, "---\n")) return null;
    const rest = text[4..];
    if (std.mem.startsWith(u8, rest, "---\n") or std.mem.eql(u8, rest, "---")) return rest[0..0];
    if (std.mem.indexOf(u8, rest, "\n---\n")) |i| return rest[0 .. i + 1];
    if (std.mem.endsWith(u8, rest, "\n---")) return rest[0 .. rest.len - 3];
    return null;
}

fn unquote(v: []const u8) []const u8 {
    if (v.len >= 2 and ((v[0] == '"' and v[v.len - 1] == '"') or (v[0] == '\'' and v[v.len - 1] == '\''))) return v[1 .. v.len - 1];
    return v;
}

/// Slices point into `text` except `description`, which is allocated in `arena`.
pub fn parse(arena: std.mem.Allocator, text: []const u8) Error!Frontmatter {
    const fm = block(text) orelse return error.InvalidArgument;
    var out: Frontmatter = .{ .name = "", .description = "", .requires_packages = "" };
    var in_metadata = false;
    var lines = std.mem.splitScalar(u8, fm, '\n');
    var pending: ?[]const u8 = null;
    while (true) {
        const line = pending orelse (lines.next() orelse break);
        pending = null;
        if (line.len == 0) continue;
        const indented = line[0] == ' ' or line[0] == '\t';
        const t = std.mem.trim(u8, line, " \t");
        if (!indented) {
            in_metadata = std.mem.eql(u8, t, "metadata:");
            if (std.mem.startsWith(u8, t, "name:")) {
                out.name = unquote(std.mem.trim(u8, t["name:".len..], " \t"));
            } else if (std.mem.startsWith(u8, t, "description:")) {
                const v = std.mem.trim(u8, t["description:".len..], " \t");
                const literal = v.len > 0 and v[0] == '|';
                const block_scalar = v.len > 0 and (v[0] == '>' or v[0] == '|');
                var buf: std.ArrayList(u8) = .empty;
                if (!block_scalar and v.len > 0) try buf.appendSlice(arena, unquote(v));
                while (lines.next()) |next| {
                    if (next.len > 0 and next[0] != ' ' and next[0] != '\t') {
                        pending = next;
                        break;
                    }
                    const piece = std.mem.trim(u8, next, " \t");
                    if (piece.len == 0) continue;
                    if (buf.items.len > 0) try buf.append(arena, if (literal) '\n' else ' ');
                    try buf.appendSlice(arena, piece);
                }
                out.description = buf.items;
            }
        } else if (in_metadata and std.mem.startsWith(u8, t, "requires-packages:")) {
            out.requires_packages = std.mem.trim(u8, t["requires-packages:".len..], " \t");
        }
    }
    return out;
}
