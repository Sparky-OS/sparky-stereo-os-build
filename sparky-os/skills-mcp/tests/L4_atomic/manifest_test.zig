//! Skills extension (SEP-2640): the manifest entry of each file. The expected digests and sizes are the ones the
//! extension's own example gives for the pdf-processing skill (beta/skills page, "supporting files"), and were
//! re-computed with sha256sum on 2026-11-06 from the fixture files, so the test checks the file, not a copy of the number.
const std = @import("std");
const manifest = @import("manifest");

fn expectEntry(uri: []const u8, bytes: []const u8, digest: []const u8, size: usize) !void {
    const e = try manifest.entry(uri, bytes);
    try std.testing.expectEqualStrings(uri, e.uri);
    try std.testing.expectEqualStrings(digest, &e.digest);
    try std.testing.expectEqual(size, e.size);
}

test "the extension's example skill gives the extension's digests and sizes" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, "data/fixtures/pdf-processing", .{});
    defer dir.close(io);
    const skill = try dir.readFileAlloc(io, "SKILL.md", a, .limited(4096));
    defer a.free(skill);
    const inv = try dir.readFileAlloc(io, "templates/invoice.md", a, .limited(4096));
    defer a.free(inv);
    const po = try dir.readFileAlloc(io, "templates/purchase-order.md", a, .limited(4096));
    defer a.free(po);
    try expectEntry("skill://pdf-processing/SKILL.md", skill, "sha256:99b737495721155ece826d57521e2d66141ebdc1344a400487481ea2642ab19e", 151);
    try expectEntry("skill://pdf-processing/templates/invoice.md", inv, "sha256:61f4ea6d2c75fde1b4977219e7e3107d491c3c26aefb6686e84d6281c088d9ee", 29);
    try expectEntry("skill://pdf-processing/templates/purchase-order.md", po, "sha256:f2ff774b1737ff3dec81c47946f9976f18a1a9f69dda0a81f22eabd95173c158", 35);
}

test "one changed byte changes the digest (negative control)" {
    const a = try manifest.entry("skill://x/SKILL.md", "abc");
    const b = try manifest.entry("skill://x/SKILL.md", "abd");
    try std.testing.expect(!std.mem.eql(u8, &a.digest, &b.digest));
}
