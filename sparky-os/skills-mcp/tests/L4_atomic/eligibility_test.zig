//! "Only what is installed is served". `a | b` means any one alternative (the shell helper's packages_allowed).
const std = @import("std");
const eligibility = @import("eligibility");

const with_pipewire = eligibility.Installed{ .names = &.{ "pipewire", "ffmpeg" } };
const without = eligibility.Installed{ .names = &.{"ffmpeg"} };

test "an empty field is always allowed" {
    try std.testing.expect(eligibility.allowed("", without));
    try std.testing.expect(eligibility.allowed("   ", without));
}

test "a single package must be installed" {
    try std.testing.expect(eligibility.allowed("pipewire", with_pipewire));
    try std.testing.expect(!eligibility.allowed("pipewire", without));
}

test "alternatives: one installed is enough, spaces do not matter" {
    try std.testing.expect(eligibility.allowed("monado-service | ffmpeg", with_pipewire));
    try std.testing.expect(eligibility.allowed("dkms|ffmpeg", without));
    try std.testing.expect(!eligibility.allowed("dkms | edid-decode", without));
}

test "a package name that merely contains an installed name is not installed" {
    try std.testing.expect(!eligibility.allowed("pipewire-audio", with_pipewire));
}
