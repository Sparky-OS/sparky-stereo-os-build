//! The command gate and the command switch through the engine, both ways, and the runner's refusals.
const std = @import("std");
const engine = @import("engine");
const testkit = @import("testkit");

const commands_json =
    \\[{"id":"say","argv":["/bin/echo","{word}"],"slots":{"word":"word"},"expect":{"exit":0,"stdout_contains":"hello"},"run":"assistant"},
    \\ {"id":"fail","argv":["/bin/false"],"slots":{},"expect":{"exit":0},"run":"assistant"},
    \\ {"id":"envdump","argv":["/usr/bin/env"],"slots":{},"run":"assistant"},
    \\ {"id":"admin","argv":["/bin/echo","x"],"slots":{},"run":"person"}]
;

const assistants = [_]engine.Assistant{.{ .id = "claude_code", .programs = &.{"claude"}, .home_dirs = &.{".claude"} }};

fn setup(a: std.mem.Allocator, io: std.Io, s: *testkit.Scratch, with_ai: bool) !engine.Engine {
    try s.write("usr/share/agent-skills/user/net-fix/SKILL.md", try testkit.skill(a, "net-fix", "Fix the network.", ""));
    try s.write("usr/share/agent-skills/user/net-fix/commands.json", commands_json);
    try s.write("usr/share/agent-skills/developer/dev-only/SKILL.md", try testkit.skill(a, "dev-only", "Developer skill.", ""));
    try s.write("usr/share/agent-skills/developer/dev-only/commands.json", commands_json);
    if (with_ai) try s.write("home/.claude/x", "");
    const root = s.path;
    const env = try testkit.env(a, &.{
        .{ "XDG_DATA_DIRS", try std.fmt.allocPrint(a, "{s}/usr/share", .{root}) },
        .{ "XDG_CONFIG_HOME", try std.fmt.allocPrint(a, "{s}/home/.config", .{root}) },
        .{ "HOME", try std.fmt.allocPrint(a, "{s}/home", .{root}) },
        .{ "PATH", "/usr/bin:/bin" },
        .{ "SECRET", "leaked" },
        .{ "LANG", "C" },
        .{ "SPARKY_STEREO_PACKAGES", "x" },
    });
    var e = try engine.Engine.init(a, io, env);
    e.assistants = &assistants;
    return e;
}

test "default policy auto: an AI tool found lets the assistant approve, none found asks the person" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s1 = try testkit.Scratch.make(io, "/tmp/skills-mcp-gate-1");
    defer s1.cleanup();
    var with = try setup(a, io, &s1, true);
    const g1 = try with.gate("net-fix", "say", .mcp);
    try std.testing.expectEqual(engine.Policy.auto, with.session.commandsPolicy());
    try std.testing.expect(g1.decision == .run_assistant_approves);
    try std.testing.expectEqual(@as(usize, 1), g1.ai_found.len);
    var s2 = try testkit.Scratch.make(io, "/tmp/skills-mcp-gate-2");
    defer s2.cleanup();
    var without = try setup(a, io, &s2, false);
    const g2 = try without.gate("net-fix", "say", .mcp);
    try std.testing.expect(g2.decision == .ask_person);
    try std.testing.expectEqual(@as(usize, 0), g2.ai_found.len);
}

test "the switch works both ways and is remembered: ask forces the question, assistant lets it run" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-gate-3");
    defer s.cleanup();
    var e = try setup(a, io, &s, true);
    try e.session.setCommandsPolicy(.ask);
    var again = try setup(a, io, &s, true);
    try std.testing.expectEqual(engine.Policy.ask, again.session.commandsPolicy());
    try std.testing.expect((try again.gate("net-fix", "say", .mcp)).decision == .ask_person);
    try again.session.setCommandsPolicy(.assistant);
    var third = try setup(a, io, &s, false);
    try std.testing.expect((try third.gate("net-fix", "say", .mcp)).decision == .run_assistant_approves);
    try std.testing.expect((try third.gate("net-fix", "admin", .mcp)).decision == .ask_person);
}

test "an unlisted command is refused, the command line always asks, developer skills list no commands" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-gate-4");
    defer s.cleanup();
    var e = try setup(a, io, &s, true);
    try std.testing.expect((try e.gate("net-fix", "rm-rf", .mcp)).decision == .refuse);
    try std.testing.expect((try e.gate("net-fix", "say", .cli)).decision == .ask_person);
    try std.testing.expectError(error.Failed, e.commands("dev-only"));
}

test "an approved command runs, expect is checked, slots are validated, nothing else is passed on" {
    var st = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer st.deinit();
    const a = st.allocator();
    const io = std.testing.io;
    var s = try testkit.Scratch.make(io, "/tmp/skills-mcp-gate-5");
    defer s.cleanup();
    var e = try setup(a, io, &s, true);
    const ok = try e.runApproved("net-fix", "say", &.{.{ .name = "word", .value = "hello" }});
    try std.testing.expectEqual(@as(?u8, 0), ok.exit_code);
    try std.testing.expect(ok.expected);
    const other = try e.runApproved("net-fix", "say", &.{.{ .name = "word", .value = "bye" }});
    try std.testing.expect(!other.expected);
    const bad = try e.runApproved("net-fix", "fail", &.{});
    try std.testing.expect(!bad.expected);
    try std.testing.expectError(error.Failed, e.runApproved("net-fix", "say", &.{.{ .name = "word", .value = "$(id)" }}));
    try std.testing.expectError(error.Failed, e.runApproved("net-fix", "say", &.{}));
    try std.testing.expectError(error.Failed, e.runApproved("net-fix", "nope", &.{}));
    const env_out = try e.runApproved("net-fix", "envdump", &.{});
    try std.testing.expect(std.mem.indexOf(u8, env_out.stdout, "SECRET") == null);
    try std.testing.expect(std.mem.indexOf(u8, env_out.stdout, "HOME=") != null);
}
