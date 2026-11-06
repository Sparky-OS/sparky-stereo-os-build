//! L4 atom: the front matter of a SKILL.md (agentskills.io specification), only the fields the engine uses.
const std = @import("std");

pub const Frontmatter = struct {
    name: []const u8,
    description: []const u8,
    /// The raw `metadata: requires-packages:` text such as "monado-service | ffmpeg"; empty when absent.
    requires_packages: []const u8,
};

/// Slices point into `text` except `description` of a block scalar, which is allocated in `arena`.
pub fn parse(arena: std.mem.Allocator, text: []const u8) !Frontmatter {
    _ = arena;
    _ = text;
    return error.NotImplemented;
}
