//! L4 atom: which relative paths and skill names may be served. Read only, contained in the skill's own folder.
//! MCP resources page: servers must validate resource URIs and sanitize file paths against directory traversal.
const std = @import("std");

pub const Error = error{ Refused, OutOfMemory };

/// A skill name: `[a-z0-9]+(-[a-z0-9]+)*`, 1 to 64 characters (agentskills.io specification).
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 64) return false;
    var prev_hyphen = true; // a leading hyphen is as bad as a doubled one
    for (name) |ch| {
        const alnum = (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9');
        if (alnum) {
            prev_hyphen = false;
        } else if (ch == '-' and !prev_hyphen) {
            prev_hyphen = true;
        } else return false;
    }
    return !prev_hyphen;
}

/// `rel` as it came from outside (a URI path, a tool argument). Returns it unchanged when safe.
pub fn check(rel: []const u8) Error![]const u8 {
    if (rel.len == 0 or rel[0] == '/') return error.Refused;
    for (rel) |ch| if (ch == 0 or ch == '\\') return error.Refused;
    var i: usize = 0;
    while (i + 2 < rel.len + 0) : (i += 1) {
        if (rel[i] == '%' and rel[i + 1] == '2' and (rel[i + 2] == 'e' or rel[i + 2] == 'E')) return error.Refused;
    }
    var segs = std.mem.splitScalar(u8, rel, '/');
    while (segs.next()) |s| {
        if (s.len == 0 or std.mem.eql(u8, s, "..") or std.mem.eql(u8, s, ".")) return error.Refused;
    }
    return rel;
}

/// After the path was resolved (realpath): it must stay inside `root`.
pub fn checkResolved(root: []const u8, resolved: []const u8) Error!void {
    if (std.mem.eql(u8, root, resolved)) return;
    if (resolved.len > root.len and std.mem.startsWith(u8, resolved, root) and resolved[root.len] == '/') return;
    return error.Refused;
}
