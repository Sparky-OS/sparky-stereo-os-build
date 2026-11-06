//! The small atoms: sections, budget, ratelimit, skill_uri, statefile, slot_class, dpkg status.
const std = @import("std");
const sections = @import("sections");
const budget = @import("budget");
const ratelimit = @import("ratelimit");
const skill_uri = @import("skill_uri");
const statefile = @import("statefile");
const slot_class = @import("slot_class");
const dpkg_status = @import("dpkg_status");

test "headings skip fenced blocks and trailing hashes" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const hs = try sections.headings(st.allocator(), "# One\n```\n## no\n```\n## Two ##\ntext\n#hash is not one\n");
    try std.testing.expectEqual(@as(usize, 2), hs.len);
    try std.testing.expectEqualStrings("Two", hs[1].title);
}

test "a section ends at the next heading of the same or a higher level" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const out = try sections.select(a, "## A\nbody a\n### A1\ninner\n## B\nbody b\n", "A");
    try std.testing.expect(std.mem.indexOf(u8, out, "inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "body b") == null);
    try std.testing.expectError(error.NotFound, sections.select(a, "## A\n", "Z"));
    try std.testing.expectError(error.Ambiguous, sections.select(a, "## A\n## A\n", "A"));
}

test "budget counts characters, not bytes" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    try std.testing.expect((try budget.overBudget(a, "ééééé", 5)) == null);
    try std.testing.expect((try budget.overBudget(a, "ééééé", 4)) != null);
}

test "the window allows 50 calls in 10 seconds, then refuses, then allows again" {
    var w = ratelimit.Window{};
    var n: usize = 0;
    var t: i64 = 1000;
    while (n < 50) : (n += 1) try std.testing.expect(w.allow(t));
    try std.testing.expect(!w.allow(t + 5));
    try std.testing.expect(w.allow(t + 10_001));
    t = 0;
}

test "skill addresses round trip and refuse other shapes" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const u = try skill_uri.format(st.allocator(), "system", "user", "pdf-processing", "templates/invoice.md");
    const p = try skill_uri.parse(u);
    try std.testing.expectEqualStrings("pdf-processing", p.name);
    try std.testing.expectEqualStrings("templates/invoice.md", p.file);
    try std.testing.expectError(error.InvalidArgument, skill_uri.parse("http://x/y"));
    try std.testing.expectError(error.InvalidArgument, skill_uri.parse("skill://a/b"));
}

test "the state file keeps every other line byte for byte" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const before = "LINK=claude\n\n# note\nMCP=claude\n";
    try std.testing.expectEqualStrings("claude", statefile.get(before, "MCP").?);
    const after = try statefile.set(a, before, "COMMANDS", "ask");
    try std.testing.expectEqualStrings("LINK=claude\n\n# note\nMCP=claude\nCOMMANDS=ask\n", after);
    try std.testing.expectEqualStrings("LINK=claude\n\n# note\n", try statefile.set(a, before, "MCP", null));
    try std.testing.expectEqualStrings("COMMANDS=auto\n", try statefile.set(a, "", "COMMANDS", "auto"));
}

test "slot classes" {
    try std.testing.expect(slot_class.matches("word", "wlan0"));
    try std.testing.expect(!slot_class.matches("word", "a b"));
    try std.testing.expect(!slot_class.matches("word", "$(id)"));
    try std.testing.expect(!slot_class.matches("word", ""));
    try std.testing.expect(slot_class.matches("int", "-42"));
    try std.testing.expect(!slot_class.matches("int", "4x"));
    try std.testing.expect(slot_class.matches("enum:on,off", "off"));
    try std.testing.expect(!slot_class.matches("enum:on,off", "of"));
    try std.testing.expect(!slot_class.matches("nonsense", "x"));
}

test "dpkg status: only installed packages count" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const names = try dpkg_status.installed(st.allocator(),
        \\Package: pipewire
        \\Status: install ok installed
        \\Version: 1
        \\
        \\Package: old
        \\Status: deinstall ok config-files
        \\
        \\Package: half
        \\Status: install ok half-installed
        \\
        \\Package: libc6
        \\Status: install ok installed
        \\
    );
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("pipewire", names[0]);
    try std.testing.expectEqualStrings("libc6", names[1]);
}
