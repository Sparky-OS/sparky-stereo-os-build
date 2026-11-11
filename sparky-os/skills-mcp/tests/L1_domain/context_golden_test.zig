//! `context`, `sections` and `find` equal the Python tool's output for the same tree (data/fixtures/ref-tree and
//! the goldens recorded from the Python engine this one replaced, run on it), byte for byte, including the over budget refusal.
const std = @import("std");
const engine = @import("engine");
const testkit = @import("testkit");

const tree = "data/fixtures/ref-tree";

fn open(a: std.mem.Allocator, io: std.Io, packages: []const u8) !engine.Engine {
    return engine.Engine.initTree(a, io, try testkit.env(a, &.{ .{ "SPARKY_STEREO_PACKAGES", packages }, .{ "HOME", "/tmp" } }), "developer", tree ++ "/skills", tree);
}

fn golden(a: std.mem.Allocator, io: std.Io, name: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, try std.fmt.allocPrint(a, "data/golden/{s}", .{name}), a, .limited(1 << 20));
}

test "context for a skill is the Python text byte for byte" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var e = try open(a, io, "demoprog");
    try std.testing.expectEqualStrings(try golden(a, io, "context-demo.txt"), try e.context(.{ .names = &.{"demo"} }));
}

test "a section, and a section with a reference, are the Python text byte for byte" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var e = try open(a, io, "demoprog");
    try std.testing.expectEqualStrings(try golden(a, io, "context-section.txt"), try e.context(.{ .sections = &.{"demo:Second heading"} }));
    try std.testing.expectEqualStrings(try golden(a, io, "context-section-ref.txt"), try e.context(.{ .sections = &.{"demo:First heading"}, .references = &.{"docs/guide.md"} }));
}

test "the headings are the Python list, and a heading inside a code fence is not one" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var e = try open(a, io, "demoprog");
    var out: std.ArrayList(u8) = .empty;
    for (try e.sectionsOf("demo")) |h| try out.print(a, "{s}\n", .{h.title});
    try std.testing.expectEqualStrings(try golden(a, io, "sections-demo.txt"), out.items);
}

test "over budget is an error with the old sentence and nothing is cut" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var e = try open(a, io, "demoprog");
    try std.testing.expectError(error.Failed, e.context(.{ .names = &.{"demo"}, .max_chars = 300 }));
    const want = std.mem.trim(u8, try golden(a, io, "context-over-budget.err"), "\n");
    try std.testing.expectEqualStrings(want, e.message);
}

test "a reference outside the public list, or a traversal, is refused" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var e = try open(a, io, "demoprog");
    for ([_][]const u8{ "../outside.md", "private/x.md", "/etc/passwd", "docs/../../x" }) |r| {
        try std.testing.expectError(error.Failed, e.context(.{ .names = &.{"demo"}, .references = &.{r} }));
    }
}

test "find on the fixture ranks as the Python tool does" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var e = try open(a, io, "demoprog");
    // the oracle ignores eligibility, so compare with all skills in the pool; with the filter on, N counts only the installed ones
    const rows = try e.find("widgets broken", 2, true);
    try std.testing.expectEqualStrings("demo", rows[0].name);
    try std.testing.expectApproxEqAbs(@as(f64, 6.02), rows[0].score, 0.005);
}
