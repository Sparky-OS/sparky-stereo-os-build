//! L4 atom: the character budget of a context bundle. Characters, not bytes and not tokens, as the Python tool counts.
const std = @import("std");

pub const default_limit: usize = 48000;

/// The sentence for the person when `text` is over `limit` characters, or null when it fits.
pub fn overBudget(arena: std.mem.Allocator, text: []const u8, limit: usize) !?[]const u8 {
    const chars = std.unicode.utf8CountCodepoints(text) catch text.len;
    if (chars <= limit) return null;
    return try std.fmt.allocPrint(arena, "Context has {d} characters; limit is {d}. Select fewer skills/sections or explicitly increase --max-chars. Nothing was truncated.", .{ chars, limit });
}
