//! The command line door: `sparky-stereo-skills find|list|sections|context|read|manifest|commands|run|mcp ...`.
//! It holds no skill logic: every verb asks the engine and prints what comes back, in the person's language where the
//! words are ours (the gate's questions), and plain English where they are the engine's.
const std = @import("std");
const engine = @import("engine");
const assistants_reg = @import("kinds_assistant");
const tools_reg = @import("kinds_tool");
const langs = @import("kinds_lang");
const proc = @import("proc");

const help_text =
    \\sparky-stereo-skills: the skills of this system, for people and for assistants.
    \\  find TEXT [--limit N] [--all]      the skills that answer a task or symptom
    \\  list [--kind KIND] [--all]         the installed skills
    \\  sections SKILL                     the exact headings of a skill
    \\  context [SKILL...] [--section SKILL:HEADING]... [--reference PATH]... [--max-chars N]
    \\  read SKILL [FILE]                  one file of a skill
    \\  manifest SKILL                     every file of a skill with its SHA-256 and size
    \\  commands SKILL                     the commands a user skill lists
    \\  run SKILL ID [SLOT=VALUE...]       run one listed command (the gate decides who must say yes)
    \\  serve                              the MCP server, over stdio, started by an assistant
    \\  mcp register|unregister|status|commands [ASSISTANT...|auto|assistant|ask]
    \\Options before the verb's own: --root DIR uses a checkout of the public tree (skills/ and its reference files).
    \\
;

const Strings = struct { confirm_run: []const u8 = "", no_ai_tool: []const u8 = "", refused_not_listed: []const u8 = "" };

pub fn assistantList() []const engine.Assistant {
    const list = comptime blk: {
        var arr: [assistants_reg.all.len]engine.Assistant = undefined;
        for (assistants_reg.all, 0..) |a, i| arr[i] = .{ .id = a.id, .programs = &a.programs, .home_dirs = &a.home_dirs };
        break :blk arr;
    };
    return &list;
}

fn strings(arena: std.mem.Allocator, e: *engine.Engine) Strings {
    var ids: [langs.all.len][]const u8 = undefined;
    inline for (langs.all, 0..) |l, i| ids[i] = l.id;
    var fallback: []const u8 = "";
    inline for (langs.all) |l| if (l.is_source) {
        fallback = l.id;
    };
    const pick = e.session.language(&ids, fallback);
    inline for (langs.all) |l| if (std.mem.eql(u8, l.id, pick)) {
        return std.json.parseFromSliceLeaky(Strings, arena, l.strings_json, .{ .ignore_unknown_fields = true }) catch return .{};
    };
    return .{};
}

const Io = struct {
    out: std.ArrayList(u8) = .empty,
    code: u8 = 0,
};

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    var o: Io = .{};
    try dispatch(init, arena, io, args, &o);
    var buf: [8192]u8 = undefined;
    var w = std.Io.File.stdout().writer(io, &buf);
    try w.interface.writeAll(o.out.items);
    try w.interface.flush();
    if (o.code != 0) std.process.exit(o.code);
}

fn say(arena: std.mem.Allocator, o: *Io, comptime fmt: []const u8, a: anytype) !void {
    try o.out.print(arena, fmt, a);
}

fn fail(arena: std.mem.Allocator, io: std.Io, o: *Io, code: u8, comptime fmt: []const u8, a: anytype) !void {
    _ = o;
    var buf: [2048]u8 = undefined;
    var w = std.Io.File.stderr().writer(io, &buf);
    try w.interface.print(fmt ++ "\n", a);
    try w.interface.flush();
    _ = arena;
    std.process.exit(code);
}

fn dispatch(init: std.process.Init, arena: std.mem.Allocator, io: std.Io, args_in: []const []const u8, o: *Io) !void {
    var args = args_in;
    var root: ?[]const u8 = null;
    if (args.len >= 2 and std.mem.eql(u8, args[0], "--root")) {
        root = args[1];
        args = args[2..];
    }
    if (args.len == 0 or std.mem.eql(u8, args[0], "help") or std.mem.eql(u8, args[0], "--help")) {
        try say(arena, o, "{s}", .{help_text});
        return;
    }
    var e = (if (root) |r|
        engine.Engine.initCheckout(arena, io, init.environ_map, r)
    else
        engine.Engine.init(arena, io, init.environ_map)) catch |err| {
        return fail(arena, io, o, 2, "The skills could not be read ({s}), so nothing is served. Check that /var/lib/dpkg/status is readable.", .{@errorName(err)});
    };
    e.assistants = assistantList();
    const verb = args[0];
    const rest = args[1..];
    const result = runVerb(init, arena, io, &e, verb, rest, o);
    result catch |err| switch (err) {
        error.Failed => return fail(arena, io, o, 2, "{s}", .{e.message}),
        error.Usage => return fail(arena, io, o, 2, "{s}", .{help_text}),
        else => return fail(arena, io, o, 2, "That did not work ({s}).", .{@errorName(err)}),
    };
}

const VerbError = error{ Failed, Usage } || anyerror;

fn flagValue(rest: []const []const u8, flag: []const u8) ?[]const u8 {
    for (rest, 0..) |a, i| if (std.mem.eql(u8, a, flag) and i + 1 < rest.len) return rest[i + 1];
    return null;
}

fn hasFlag(rest: []const []const u8, flag: []const u8) bool {
    for (rest) |a| if (std.mem.eql(u8, a, flag)) return true;
    return false;
}

/// The arguments that are not flags or flag values, with `with_value` flags consuming their value.
fn positionals(arena: std.mem.Allocator, rest: []const []const u8, with_value: []const []const u8, boolean: []const []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    outer: while (i < rest.len) : (i += 1) {
        for (with_value) |f| if (std.mem.eql(u8, rest[i], f)) {
            i += 1;
            continue :outer;
        };
        for (boolean) |f| if (std.mem.eql(u8, rest[i], f)) continue :outer;
        try out.append(arena, rest[i]);
    }
    return out.items;
}

fn runVerb(init: std.process.Init, arena: std.mem.Allocator, io: std.Io, e: *engine.Engine, verb: []const u8, rest: []const []const u8, o: *Io) VerbError!void {
    if (std.mem.eql(u8, verb, "find")) {
        const pos = try positionals(arena, rest, &.{"--limit"}, &.{"--all"});
        if (pos.len == 0) return error.Usage;
        const limit: usize = if (flagValue(rest, "--limit")) |v| std.fmt.parseInt(usize, v, 10) catch return error.Usage else 3;
        const query = try std.mem.join(arena, " ", pos);
        const rows = try e.find(query, limit, hasFlag(rest, "--all"));
        if (rows.len == 0) {
            try say(arena, o, "No skill matches those words. Read the task table in the skills index (list shows every skill).\n", .{});
            o.code = 1;
            return;
        }
        for (rows) |r| try say(arena, o, "{d}. {s} (score {d:.2})\n   {s}\n   {s}/SKILL.md\n   Next: sparky-stereo-skills context {s}\n", .{ r.rank, r.name, r.score, r.description, r.dir, r.name });
        return;
    }
    if (std.mem.eql(u8, verb, "list")) {
        for (try e.list(flagValue(rest, "--kind"), hasFlag(rest, "--all"))) |r| {
            try say(arena, o, "{s}\t{s}\t{s}\t{s}{s}\n", .{ r.name, r.kind, @tagName(r.origin), if (r.eligible) "" else "(package not installed) ", r.description });
        }
        return;
    }
    if (std.mem.eql(u8, verb, "sections")) {
        if (rest.len != 1) return error.Usage;
        for (try e.sectionsOf(rest[0])) |h| try say(arena, o, "{s}\n", .{h.title});
        return;
    }
    if (std.mem.eql(u8, verb, "context")) {
        var names: std.ArrayList([]const u8) = .empty;
        var secs: std.ArrayList([]const u8) = .empty;
        var refs: std.ArrayList([]const u8) = .empty;
        var max: usize = 48000;
        var i: usize = 0;
        while (i < rest.len) : (i += 1) {
            const a = rest[i];
            if (std.mem.eql(u8, a, "--section") and i + 1 < rest.len) {
                i += 1;
                try secs.append(arena, rest[i]);
            } else if (std.mem.eql(u8, a, "--reference") and i + 1 < rest.len) {
                i += 1;
                try refs.append(arena, rest[i]);
            } else if (std.mem.eql(u8, a, "--max-chars") and i + 1 < rest.len) {
                i += 1;
                max = std.fmt.parseInt(usize, rest[i], 10) catch return error.Usage;
                if (max == 0) return error.Usage;
            } else if (a.len > 0 and a[0] == '-') return error.Usage else try names.append(arena, a);
        }
        try say(arena, o, "{s}", .{try e.context(.{ .names = names.items, .sections = secs.items, .references = refs.items, .max_chars = max })});
        return;
    }
    if (std.mem.eql(u8, verb, "read")) {
        if (rest.len < 1 or rest.len > 2) return error.Usage;
        try say(arena, o, "{s}", .{try e.read(rest[0], null, if (rest.len == 2) rest[1] else "SKILL.md")});
        return;
    }
    if (std.mem.eql(u8, verb, "manifest")) {
        if (rest.len != 1) return error.Usage;
        for (try e.manifestOf(rest[0], null)) |m| try say(arena, o, "{s}\t{s}\t{d}\n", .{ m.uri, &m.digest, m.size });
        return;
    }
    if (std.mem.eql(u8, verb, "commands")) {
        if (rest.len != 1) return error.Usage;
        for (try e.commands(rest[0])) |c| {
            try say(arena, o, "{s}\t{s}\t", .{ c.id, @tagName(c.marked) });
            for (c.argv, 0..) |a, k| try say(arena, o, "{s}{s}", .{ if (k > 0) " " else "", a });
            try say(arena, o, "\n", .{});
        }
        return;
    }
    if (std.mem.eql(u8, verb, "run")) return runCommand(init, arena, io, e, rest, o);
    if (std.mem.eql(u8, verb, "mcp")) return mcp(init, arena, io, e, rest, o);
    return error.Usage;
}

fn runCommand(init: std.process.Init, arena: std.mem.Allocator, io: std.Io, e: *engine.Engine, rest: []const []const u8, o: *Io) VerbError!void {
    if (rest.len < 2) return error.Usage;
    const g = try e.gate(rest[0], rest[1], .cli);
    const s = strings(arena, e);
    switch (g.decision) {
        .refuse => |why| {
            try say(arena, o, "{s}\n", .{if (s.refused_not_listed.len > 0 and g.cmd == null) s.refused_not_listed else why});
            o.code = 1;
            return;
        },
        else => {},
    }
    var values: std.ArrayList(engine.RunValue) = .empty;
    for (rest[2..]) |kv| {
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse return error.Usage;
        try values.append(arena, .{ .name = kv[0..eq], .value = kv[eq + 1 ..] });
    }
    // The command line always asks: the person at the keyboard is the one who says yes.
    var line_text: std.ArrayList(u8) = .empty;
    for (g.cmd.?.argv, 0..) |a, k| {
        var shown = a;
        if (a.len >= 3 and a[0] == '{' and a[a.len - 1] == '}') for (values.items) |v| if (std.mem.eql(u8, v.name, a[1 .. a.len - 1])) {
            shown = v.value;
        };
        try line_text.print(arena, "{s}{s}", .{ if (k > 0) " " else "", shown });
    }
    if (g.ai_found.len == 0 and e.session.commandsPolicy() == .auto and s.no_ai_tool.len > 0) try say(arena, o, "{s}\n", .{s.no_ai_tool});
    var prompt_buf: [2048]u8 = undefined;
    var ew = std.Io.File.stderr().writer(io, &prompt_buf);
    const q = try std.mem.replaceOwned(u8, arena, if (s.confirm_run.len > 0) s.confirm_run else "Run this command? {s}", "{s}", line_text.items);
    try ew.interface.print("{s} [y/N] ", .{q});
    try ew.interface.flush();
    var in_buf: [256]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buf);
    const answer = (stdin.interface.takeDelimiter('\n') catch null) orelse "";
    const yes = std.ascii.eqlIgnoreCase(std.mem.trim(u8, answer, " \t\r"), "y") or std.ascii.eqlIgnoreCase(std.mem.trim(u8, answer, " \t\r"), "yes");
    if (!yes) {
        try say(arena, o, "Not run.\n", .{});
        o.code = 1;
        return;
    }
    _ = init;
    const r = try e.runApproved(rest[0], rest[1], values.items);
    try say(arena, o, "{s}", .{r.stdout});
    if (r.stderr.len > 0) try say(arena, o, "{s}", .{r.stderr});
    try say(arena, o, "exit {?d}{s}; expected result {s}\n", .{ r.exit_code, if (r.timed_out) " (timed out)" else "", if (r.expected) "matched" else "NOT matched" });
    if (!r.expected or r.exit_code == null or r.exit_code.? != 0) o.code = 1;
}

fn mcp(init: std.process.Init, arena: std.mem.Allocator, io: std.Io, e: *engine.Engine, rest: []const []const u8, o: *Io) VerbError!void {
    _ = init;
    if (rest.len == 0) return error.Usage;
    const sub = rest[0];
    const want = rest[1..];
    if (std.mem.eql(u8, sub, "commands")) {
        if (want.len == 0) {
            const p = e.session.commandsPolicy();
            const found = try e.session.assistantsFound(e.assistants);
            try say(arena, o, "commands policy: {s}\nassistants found on this system: {d}\n", .{ @tagName(p), found.len });
            try say(arena, o, "auto: with an AI assistant on this system its own approval applies, without one every command asks you first.\nassistant: the assistant's approval always applies.\nask: every command asks you first.\n", .{});
            return;
        }
        const p = engine.parsePolicy(want[0]) orelse return error.Usage;
        e.session.setCommandsPolicy(p) catch return e.fail("The choice could not be saved: there is no home folder.", .{});
        try say(arena, o, "commands policy: {s}\n", .{@tagName(p)});
        return;
    }
    if (std.mem.eql(u8, sub, "status")) {
        try say(arena, o, "server: sparky-stereo-skills (stdio), tools: {d}, installed skills: {d}\n", .{ tools_reg.names.len, (try e.list(null, false)).len });
        try say(arena, o, "commands policy: {s}\n", .{@tagName(e.session.commandsPolicy())});
        const reg = e.session.registered();
        try say(arena, o, "registered with: {s}\n", .{if (reg.len == 0) "no assistant" else reg});
        inline for (assistants_reg.all) |a| {
            if (std.mem.indexOf(u8, reg, a.id) != null) {
                const r = proc.run(arena, io, .{ .argv = a.list_argv, .env = e.session.env, .timeout_ms = 15_000 }) catch |err| {
                    try say(arena, o, "{s}: could not ask ({s})\n", .{ a.id, @errorName(err) });
                    return;
                };
                const there = std.mem.indexOf(u8, r.stdout, "sparky-stereo-skills") != null;
                try say(arena, o, "{s}: {s}\n", .{ a.id, if (there) "the assistant lists the server" else "the assistant does NOT list the server" });
            }
        }
        return;
    }
    const registering = std.mem.eql(u8, sub, "register");
    if (!registering and !std.mem.eql(u8, sub, "unregister")) return error.Usage;
    var ids: std.ArrayList([]const u8) = .empty;
    if (want.len > 0) {
        for (want) |w| try ids.append(arena, w);
    } else if (registering) {
        for (try e.session.assistantsFound(e.assistants)) |f| try ids.append(arena, f);
    } else {
        var it = std.mem.tokenizeScalar(u8, e.session.registered(), ' ');
        while (it.next()) |t| try ids.append(arena, t);
    }
    if (ids.items.len == 0) {
        try say(arena, o, "No assistant to {s}: name one ({s}).\n", .{ sub, "claude_code, codex, gemini_cli, opencode, cline" });
        o.code = 1;
        return;
    }
    var now: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, e.session.registered(), ' ');
    while (it.next()) |t| try now.print(arena, "{s}{s}", .{ if (now.items.len > 0) " " else "", t });
    for (ids.items) |id| {
        const known = lookup(id);
        if (known) |a| {
            const argv: []const []const u8 = if (registering) a.register_argv else a.unregister_argv;
            if (argv.len == 0) {
                try say(arena, o, "{s}: there is no command for this; {s}\n", .{ id, a.unregister_note });
                o.code = 1;
                continue;
            }
            try say(arena, o, "{s}: running", .{id});
            for (argv) |x| try say(arena, o, " {s}", .{x});
            try say(arena, o, "\n", .{});
            const r = proc.run(arena, io, .{ .argv = argv, .env = e.session.env, .timeout_ms = 60_000 }) catch |err| {
                try say(arena, o, "{s}: could not run it ({s}). Is {s} installed?\n", .{ id, @errorName(err), argv[0] });
                o.code = 1;
                continue;
            };
            try say(arena, o, "{s}{s}", .{ r.stdout, r.stderr });
            if (r.exit_code == null or r.exit_code.? != 0) {
                try say(arena, o, "{s}: the assistant refused (exit {?d}); nothing was recorded.\n", .{ id, r.exit_code });
                o.code = 1;
                continue;
            }
            var updated: std.ArrayList(u8) = .empty;
            var cur = std.mem.tokenizeScalar(u8, now.items, ' ');
            var have = false;
            while (cur.next()) |t| {
                if (std.mem.eql(u8, t, id)) {
                    have = true;
                    if (!registering) continue;
                }
                try updated.print(arena, "{s}{s}", .{ if (updated.items.len > 0) " " else "", t });
            }
            if (registering and !have) try updated.print(arena, "{s}{s}", .{ if (updated.items.len > 0) " " else "", id });
            now = updated;
            e.session.setRegistered(now.items) catch {};
            try say(arena, o, "{s}: done\n", .{id});
        }
        if (known == null) {
            try say(arena, o, "{s}: not an assistant this program knows how to register with\n", .{id});
            o.code = 1;
        }
    }
}

const AssistantInfo = struct {
    id: []const u8,
    register_argv: []const []const u8,
    unregister_argv: []const []const u8,
    unregister_note: []const u8,
};

fn lookup(id: []const u8) ?AssistantInfo {
    inline for (assistants_reg.all) |a| {
        if (std.mem.eql(u8, a.id, id)) return .{ .id = a.id, .register_argv = a.register_argv, .unregister_argv = a.unregister_argv, .unregister_note = a.unregister_note };
    }
    return null;
}
