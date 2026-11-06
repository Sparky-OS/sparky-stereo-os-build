//! L4 atom: which relative paths and skill names may be served. Read only, contained in the skill's own folder.
const std = @import("std");

pub const Error = error{ Refused, OutOfMemory };

/// A skill name: `[a-z0-9]+(-[a-z0-9]+)*`, 1 to 64 characters.
pub fn validName(name: []const u8) bool {
    _ = name;
    return false;
}

/// `rel` as it came from outside (a URI path, a tool argument). Returns it unchanged when safe.
pub fn check(rel: []const u8) Error![]const u8 {
    _ = rel;
    return error.Refused;
}

/// After the path was resolved (realpath): it must stay inside `root`.
pub fn checkResolved(root: []const u8, resolved: []const u8) Error!void {
    _ = root;
    _ = resolved;
    return error.Refused;
}
