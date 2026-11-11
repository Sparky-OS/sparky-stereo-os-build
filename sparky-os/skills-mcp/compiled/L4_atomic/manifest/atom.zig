//! L4 atom: one manifest entry of the Skills extension, `{uri, digest, size}` (io.modelcontextprotocol/skills).
const std = @import("std");
const sha256 = @import("sha256");

pub const Entry = struct {
    uri: []const u8,
    /// "sha256:" followed by 64 lowercase hex digits.
    digest: [7 + sha256.hex_len]u8,
    size: usize,
};

pub fn entry(uri: []const u8, bytes: []const u8) !Entry {
    var e: Entry = .{ .uri = uri, .digest = undefined, .size = bytes.len };
    @memcpy(e.digest[0..7], "sha256:");
    @memcpy(e.digest[7..], &sha256.hex(bytes));
    return e;
}
