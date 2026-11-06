//! L6 primitive: SHA-256 as the lowercase hex text that the Skills extension writes after `sha256:`.
const std = @import("std");

pub const hex_len = 64;

pub fn hex(bytes: []const u8) [hex_len]u8 {
    var raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &raw, .{});
    return std.fmt.bytesToHex(raw, .lower);
}
