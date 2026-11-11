//! agentskills.io specification: a SKILL.md opens with YAML front matter holding `name` and `description`;
//! the edition keeps `requires-packages` under `metadata:`.
const std = @import("std");
const frontmatter = @import("frontmatter");

test "plain fields and requires-packages under metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try frontmatter.parse(arena.allocator(),
        \\---
        \\metadata:
        \\  requires-packages: monado-service | ffmpeg
        \\name: 3d-to-vr
        \\description: Stereo content in a headset.
        \\---
        \\
        \\# Body
        \\
    );
    try std.testing.expectEqualStrings("3d-to-vr", f.name);
    try std.testing.expectEqualStrings("Stereo content in a headset.", f.description);
    try std.testing.expectEqualStrings("monado-service | ffmpeg", f.requires_packages);
}

test "a >- block scalar folds its lines with single spaces (the audio skill's shape)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try frontmatter.parse(arena.allocator(),
        \\---
        \\metadata:
        \\  requires-packages: pipewire
        \\name: audio
        \\description: >-
        \\  PipeWire, WirePlumber and KDE's Sound page in the edition: the audio house format,
        \\  routing the streams KDE hides.
        \\---
        \\body
        \\
    );
    try std.testing.expectEqualStrings("audio", f.name);
    try std.testing.expectEqualStrings("PipeWire, WirePlumber and KDE's Sound page in the edition: the audio house format, routing the streams KDE hides.", f.description);
    try std.testing.expectEqualStrings("pipewire", f.requires_packages);
}

test "no requires-packages gives an empty field, so the skill is always eligible" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try frontmatter.parse(arena.allocator(), "---\nname: a\ndescription: b\n---\n");
    try std.testing.expectEqualStrings("", f.requires_packages);
}

test "front matter that never closes is an error, not an empty skill" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidArgument, frontmatter.parse(arena.allocator(), "---\nname: a\ndescription: b\n"));
    try std.testing.expectError(error.InvalidArgument, frontmatter.parse(arena.allocator(), "no front matter at all\n"));
}
