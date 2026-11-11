//! The engine through its facade, on trees built in a scratch folder: roots, kinds, eligibility, ambiguity,
//! containment, the command gate and the command switch. Each rule has a case that fails when the rule is removed.
const std = @import("std");
const engine = @import("engine");
const testkit = @import("testkit");

fn arenaState() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(std.testing.allocator);
}

fn names(recs: []const engine.Rec, a: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (recs) |r| try out.print(a, "{s} ", .{r.name});
    return out.items;
}

test "a skill exists exactly while its package's files do (a second package adds and loses a skill)" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-engine-1");
    defer s.cleanup();
    const env = try testkit.env(a, &.{ .{ "XDG_DATA_DIRS", "/tmp/skills-mcp-engine-1/usr/share" }, .{ "HOME", "/tmp/skills-mcp-engine-1/home" }, .{ "SPARKY_STEREO_PACKAGES", "base" } });
    try s.write("usr/share/agent-skills/user/first-aid/SKILL.md", try testkit.skill(a, "first-aid", "Fix the first thing.", ""));
    var e = try engine.Engine.init(a, io, env);
    try std.testing.expectEqualStrings("first-aid ", try names(try e.list(null, false), a));
    try s.write("usr/share/agent-skills/user/zz-test/SKILL.md", try testkit.skill(a, "zz-test", "A second package's skill.", ""));
    try e.refresh();
    try std.testing.expectEqualStrings("first-aid zz-test ", try names(try e.list(null, false), a));
    try s.remove("usr/share/agent-skills/user/zz-test");
    try e.refresh();
    try std.testing.expectEqualStrings("first-aid ", try names(try e.list(null, false), a));
}

test "only what is installed is served, by every operation, and all shows the rest" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-engine-2");
    defer s.cleanup();
    const env = try testkit.env(a, &.{ .{ "XDG_DATA_DIRS", "/tmp/skills-mcp-engine-2/usr/share" }, .{ "HOME", "/tmp/skills-mcp-engine-2/home" }, .{ "SPARKY_STEREO_PACKAGES", "ffmpeg" } });
    try s.write("usr/share/agent-skills/developer/audio/SKILL.md", try testkit.skill(a, "audio", "PipeWire and the Sound page: no sound after login pipewire wireplumber", "pipewire"));
    try s.write("usr/share/agent-skills/developer/video/SKILL.md", try testkit.skill(a, "video", "Players and encoders", "mpv | ffmpeg"));
    var e = try engine.Engine.init(a, io, env);
    const rows = try e.find("no sound after login pipewire wireplumber", 3, false);
    for (rows) |r| try std.testing.expect(!std.mem.eql(u8, r.name, "audio"));
    const with_all = try e.find("no sound after login pipewire wireplumber", 3, true);
    try std.testing.expectEqualStrings("audio", with_all[0].name);
    try std.testing.expectEqualStrings("video ", try names(try e.list(null, false), a));
    try std.testing.expectEqualStrings("audio video ", try names(try e.list(null, true), a));
    try std.testing.expectError(error.Failed, e.resolve("audio", null));
    try std.testing.expect(std.mem.indexOf(u8, e.message, "pipewire") != null);
}

test "one name in two origins is listed twice and refused when ambiguous, with both addresses" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-engine-3");
    defer s.cleanup();
    const env = try testkit.env(a, &.{ .{ "XDG_DATA_HOME", "/tmp/skills-mcp-engine-3/home/.local/share" }, .{ "XDG_DATA_DIRS", "/tmp/skills-mcp-engine-3/usr/share" }, .{ "HOME", "/tmp/skills-mcp-engine-3/home" }, .{ "SPARKY_STEREO_PACKAGES", "x" } });
    try s.write("usr/share/agent-skills/user/same/SKILL.md", try testkit.skill(a, "same", "System copy.", ""));
    try s.write("home/.local/share/agent-skills/user/same/SKILL.md", try testkit.skill(a, "same", "The person's copy.", ""));
    var e = try engine.Engine.init(a, io, env);
    try std.testing.expectEqual(@as(usize, 2), (try e.list(null, false)).len);
    try std.testing.expectError(error.Failed, e.resolve("same", null));
    try std.testing.expect(std.mem.indexOf(u8, e.message, "skill://system/user/same/SKILL.md") != null);
    try std.testing.expect(std.mem.indexOf(u8, e.message, "skill://user/user/same/SKILL.md") != null);
    const mine = try e.resolve("same", .user);
    try std.testing.expectEqualStrings("The person's copy.", mine.description);
}

test "an unknown kind folder and a name that differs from its folder are reported, not ignored" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-engine-4");
    defer s.cleanup();
    const env = try testkit.env(a, &.{ .{ "XDG_DATA_DIRS", "/tmp/skills-mcp-engine-4/usr/share" }, .{ "HOME", "/tmp/skills-mcp-engine-4/h" }, .{ "SPARKY_STEREO_PACKAGES", "x" } });
    try s.write("usr/share/agent-skills/mystery/odd/SKILL.md", try testkit.skill(a, "odd", "d", ""));
    try s.write("usr/share/agent-skills/user/folder-name/SKILL.md", try testkit.skill(a, "other-name", "d", ""));
    var e = try engine.Engine.init(a, io, env);
    try std.testing.expectEqual(@as(usize, 0), (try e.list(null, true)).len);
    try std.testing.expectEqual(@as(usize, 2), e.problems.items.len);
}

test "paths.d names a tree that stays where it is" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-engine-5");
    defer s.cleanup();
    const env = try testkit.env(a, &.{ .{ "XDG_DATA_DIRS", "/tmp/skills-mcp-engine-5/usr/share" }, .{ "HOME", "/tmp/skills-mcp-engine-5/h" }, .{ "SPARKY_STEREO_PACKAGES", "x" } });
    try s.write("usr/share/agent-skills/paths.d/edition.conf", "# the edition's tree\ndeveloper /tmp/skills-mcp-engine-5/usr/share/edition/skills\n");
    try s.write("usr/share/edition/skills/drivers/SKILL.md", try testkit.skill(a, "drivers", "Kernel drivers.", ""));
    var e = try engine.Engine.init(a, io, env);
    const l = try e.list("developer", false);
    try std.testing.expectEqual(@as(usize, 1), l.len);
    try std.testing.expectEqualStrings("drivers", l[0].name);
}

test "read stays inside the skill: traversal, a symlink out, and a big or non-text file are refused" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-engine-6");
    defer s.cleanup();
    const env = try testkit.env(a, &.{ .{ "XDG_DATA_DIRS", "/tmp/skills-mcp-engine-6/usr/share" }, .{ "HOME", "/tmp/skills-mcp-engine-6/h" }, .{ "SPARKY_STEREO_PACKAGES", "x" } });
    try s.write("usr/share/agent-skills/user/safe/SKILL.md", try testkit.skill(a, "safe", "d", ""));
    try s.write("usr/share/agent-skills/user/safe/references/a.md", "reference\n");
    try s.write("usr/share/agent-skills/user/safe/binary.bin", "\xff\xfe\x00\x01");
    try s.write("usr/share/agent-skills/user/safe/big.md", &([_]u8{'x'} ** (300 * 1024)));
    const dir = try s.dir.openDir(io, "usr/share/agent-skills/user/safe", .{});
    try dir.symLink(io, "/etc/hostname", "leak.md", .{});
    var e = try engine.Engine.init(a, io, env);
    try std.testing.expectEqualStrings("reference\n", try e.read("safe", null, "references/a.md"));
    for ([_][]const u8{ "../x", "/etc/passwd", "%2e%2e/x", "references/../../x" }) |p| {
        try std.testing.expectError(error.Failed, e.read("safe", null, p));
    }
    try std.testing.expectError(error.Failed, e.read("safe", null, "leak.md"));
    try std.testing.expect(std.mem.indexOf(u8, e.message, "not inside") != null);
    try std.testing.expectError(error.Failed, e.read("safe", null, "big.md"));
    try std.testing.expect(std.mem.indexOf(u8, e.message, "256 KiB") != null);
    try std.testing.expectError(error.Failed, e.read("safe", null, "binary.bin"));
}

test "the manifest digests equal the Skills extension's example" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var e = try engine.Engine.initTree(a, io, try testkit.env(a, &.{ .{ "SPARKY_STEREO_PACKAGES", "x" }, .{ "HOME", "/tmp" } }), "user", "data/fixtures", null);
    const m = try e.manifestOf("pdf-processing", null);
    try std.testing.expectEqual(@as(usize, 3), m.len);
    try std.testing.expectEqualStrings("skill://system/user/pdf-processing/SKILL.md", m[0].uri);
    try std.testing.expectEqualStrings("sha256:99b737495721155ece826d57521e2d66141ebdc1344a400487481ea2642ab19e", &m[0].digest);
    try std.testing.expectEqual(@as(usize, 151), m[0].size);
    try std.testing.expectEqualStrings("sha256:61f4ea6d2c75fde1b4977219e7e3107d491c3c26aefb6686e84d6281c088d9ee", &m[1].digest);
    try std.testing.expectEqualStrings("sha256:f2ff774b1737ff3dec81c47946f9976f18a1a9f69dda0a81f22eabd95173c158", &m[2].digest);
}

test "an empty SPARKY_STEREO_PACKAGES is no override: dpkg's own status file decides" {
    var st = arenaState();
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-engine-7");
    defer s.cleanup();
    const env = try testkit.env(a, &.{ .{ "XDG_DATA_DIRS", "/tmp/skills-mcp-engine-7/usr/share" }, .{ "HOME", "/tmp/skills-mcp-engine-7/h" }, .{ "SPARKY_STEREO_PACKAGES", "" } });
    try s.write("usr/share/agent-skills/developer/needs-dpkg/SKILL.md", try testkit.skill(a, "needs-dpkg", "Needs dpkg.", "dpkg"));
    try s.write("usr/share/agent-skills/developer/needs-absent/SKILL.md", try testkit.skill(a, "needs-absent", "Needs an absent package.", "zz-no-such-package"));
    var e = try engine.Engine.init(a, io, env);
    try std.testing.expectEqualStrings("needs-dpkg ", try names(try e.list(null, false), a));
}
