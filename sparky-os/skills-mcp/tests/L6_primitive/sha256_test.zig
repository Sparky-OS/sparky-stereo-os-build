//! Control: the one primitive that works at 2a, so a green run proves the harness can pass.
const std = @import("std");
const sha256 = @import("sha256");

test "sha256 of the empty string and of abc" {
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", &sha256.hex(""));
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &sha256.hex("abc"));
}
