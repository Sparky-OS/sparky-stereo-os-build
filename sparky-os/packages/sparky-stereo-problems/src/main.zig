// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// sparky-stereo-problems, the command: what shell scripts, maintainer scripts and people call (engine.zig is the
// engine; libsparky-stereo-problems.so is the same engine for C, C++ and Python).

const std = @import("std");
const engine = @import("engine.zig");
const sys = @import("sys.zig");

const Value = std.json.Value;
const Ctx = engine.Ctx;
const Scope = engine.Scope;

// The usage, each description in the person's language (the engine's own messages); the command lines are syntax
const Line = struct { syntax: []const u8, what: []const u8 };
const usage_lines = [_]Line{
    .{ .syntax = "keep [SCOPE] [OPTIONS] PACKAGE KEY MESSAGE [ARG...]", .what = "LOCAL38" },
    .{ .syntax = "run [SCOPE] [OPTIONS] PACKAGE KEY MESSAGE [ARG...] -- COMMAND [ARG...]", .what = "LOCAL39" },
    .{ .syntax = "clear [SCOPE] PACKAGE KEY", .what = "LOCAL40" },
    .{ .syntax = "clear --all PACKAGE", .what = "LOCAL46" },
    .{ .syntax = "say PACKAGE MESSAGE [ARG...]", .what = "LOCAL41" },
    .{ .syntax = "list [--json] [--lang LANGUAGES] [PACKAGE]", .what = "LOCAL42" },
    .{ .syntax = "repair [SCOPE] PACKAGE [KEY]", .what = "LOCAL43" },
    .{ .syntax = "hide [SCOPE] PACKAGE KEY", .what = "LOCAL44" },
    .{ .syntax = "show [SCOPE] PACKAGE KEY", .what = "LOCAL45" },
    .{ .syntax = "catalog PACKAGE DIR OUTDIR [--subject KEY[=MESSAGE,...]]... [--keys MESSAGE,...] [--context PREFIX]... [--domain NAME]", .what = "LOCAL47" },
    .{ .syntax = "text [SCOPE] [--lang LANGUAGES] PACKAGE KEY", .what = "LOCAL63" },
    .{ .syntax = "service-failed [UNIT]", .what = "LOCAL48" },
};
const options =
    \\  --severity failed|degraded|notice  --repair JSON-ARRAY  --command JSON-ARRAY  --status N
    \\  --output TEXT  --output-file FILE  --action '{"id":..,"label":[MESSAGE,ARG...],"command":[..]}'
    \\  --unit UNIT  --details JSON-OBJECT  --quiet
    \\
;

fn usageText(ctx: *Ctx) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const say = struct {
        fn f(c: *Ctx, msg: []const u8, args: []const Value) ![]const u8 {
            return (try engine.render(c, engine.engine_package, msg, args, null)).text;
        }
    }.f;
    try out.print(ctx.a, "{s}\n", .{try say(ctx, "LOCAL37", &.{.{ .string = "sparky-stereo-problems" }})});
    for (usage_lines) |l| try out.print(ctx.a, "  {s}\n        {s}\n", .{ l.syntax, try say(ctx, l.what, &.{}) });
    try out.print(ctx.a, "  message-id PACKAGE MESSAGE | languages | --version\n{s}\n{s}\n{s}{s}\n{s}\n", .{
        try say(ctx, "LOCAL49", &.{}), try say(ctx, "LOCAL60", &.{}), options, try say(ctx, "LOCAL50", &.{}), try say(ctx, "LOCAL51", &.{}),
    });
    return out.items;
}

fn err(text: []const u8) void {
    _ = engine.writeAll(2, text);
}

// A wrong use: what is wrong, in the person's language and in English, then the usage
fn wrongUse(ctx: *Ctx, msg: []const u8, args: []const []const u8) u8 {
    engine.setErr(ctx, msg, args) catch {};
    _ = said(ctx);
    err(usageText(ctx) catch "");
    return 2;
}

// What failed, in the person's language, and in English too when that is another, for support
fn said(ctx: *Ctx) u8 {
    err("sparky-stereo-problems: ");
    err(ctx.err_local);
    err("\n");
    if (!std.mem.eql(u8, ctx.err_lang, "en")) {
        err("sparky-stereo-problems: (en) ");
        err(ctx.err_en);
        err("\n");
    }
    return 1;
}

// A kept problem said on standard error, in the person's language and in English when that is another (a maintainer
// script's output, a terminal): unless --quiet
fn sayRecord(ctx: *Ctx, r: engine.Record) !void {
    const local = try engine.renderRecord(ctx, r, null);
    err(try std.mem.concat(ctx.a, u8, &.{ r.package, ": ", local.text, "\n" }));
    if (!std.mem.eql(u8, local.lang, "en")) err(try std.mem.concat(ctx.a, u8, &.{ r.package, ": (en) ", r.text_en, "\n" }));
}

// The journal's own failure is said apart, after what was asked, without taking the place of its failure
fn journalNote(ctx: *Ctx) void {
    const e = ctx.journal_error orelse return;
    const args = [_]Value{.{ .string = e }};
    const local = engine.render(ctx, engine.engine_package, "LOCAL26", &args, null) catch return;
    err("sparky-stereo-problems: ");
    err(local.text);
    err("\n");
    if (!std.mem.eql(u8, local.lang, "en")) {
        const en = engine.render(ctx, engine.engine_package, "LOCAL26", &args, "en") catch return;
        err("sparky-stereo-problems: (en) ");
        err(en.text);
        err("\n");
    }
}

const Parsed = struct {
    scope: ?Scope = null,
    record: engine.Record = .{ .package = "", .key = "", .message = "" },
    positional: std.ArrayList([]const u8) = .empty,
    command: ?[]const []const u8 = null,
    json: bool = false,
    lang: ?[]const u8 = null,
    repairs: std.ArrayList([]const []const u8) = .empty,
    actions: std.ArrayList(engine.Action) = .empty,
    subjects: std.ArrayList(engine.SubjectRule) = .empty,
    keys: ?[]const []const u8 = null,
    contexts: std.ArrayList([]const u8) = .empty,
    domain: ?[]const u8 = null,
    all: bool = false,
    quiet: bool = false,
    bad: ?[]const u8 = null,
};

fn parseJson(ctx: *Ctx, text: []const u8) ?Value {
    return std.json.parseFromSliceLeaky(Value, ctx.a, text, .{}) catch null;
}

fn parse(ctx: *Ctx, args: []const []const u8) !Parsed {
    var p = Parsed{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (std.mem.eql(u8, x, "--")) {
            p.command = args[i + 1 ..];
            break;
        }
        if (!std.mem.startsWith(u8, x, "--")) {
            try p.positional.append(ctx.a, x);
            continue;
        }
        if (Scope.parse(x[2..])) |s| {
            p.scope = s;
            continue;
        }
        if (std.mem.eql(u8, x, "--json")) {
            p.json = true;
            continue;
        }
        if (std.mem.eql(u8, x, "--all")) {
            p.all = true;
            continue;
        }
        if (std.mem.eql(u8, x, "--quiet")) {
            p.quiet = true;
            continue;
        }
        if (i + 1 >= args.len) {
            p.bad = x;
            return p;
        }
        const v = args[i + 1];
        i += 1;
        if (std.mem.eql(u8, x, "--lang")) {
            p.lang = v;
        } else if (std.mem.eql(u8, x, "--severity")) {
            p.record.severity = engine.Severity.parse(v) orelse {
                p.bad = x;
                return p;
            };
        } else if (std.mem.eql(u8, x, "--repair")) {
            const list = engine.stringList(ctx.a, parseJson(ctx, v) orelse .null) catch null;
            if (list == null or list.?.len == 0) {
                p.bad = x;
                return p;
            }
            try p.repairs.append(ctx.a, list.?);
        } else if (std.mem.eql(u8, x, "--command")) {
            p.record.command = engine.stringList(ctx.a, parseJson(ctx, v) orelse .null) catch {
                p.bad = x;
                return p;
            };
        } else if (std.mem.eql(u8, x, "--status")) {
            p.record.status = std.fmt.parseInt(i64, v, 10) catch {
                p.bad = x;
                return p;
            };
        } else if (std.mem.eql(u8, x, "--output")) {
            p.record.output = v;
        } else if (std.mem.eql(u8, x, "--output-file")) {
            p.record.output = engine.readFile(ctx.a, v) catch {
                p.bad = x;
                return p;
            };
        } else if (std.mem.eql(u8, x, "--action")) {
            const act = engine.parseAction(ctx.a, parseJson(ctx, v) orelse .null) catch {
                p.bad = x;
                return p;
            };
            try p.actions.append(ctx.a, act);
        } else if (std.mem.eql(u8, x, "--unit")) {
            p.record.unit = v;
        } else if (std.mem.eql(u8, x, "--details")) {
            const d = parseJson(ctx, v) orelse .null;
            if (d != .object) {
                p.bad = x;
                return p;
            }
            engine.applyDetails(ctx.a, &p.record, d.object) catch {
                p.bad = x;
                return p;
            };
        } else if (std.mem.eql(u8, x, "--subject")) {
            if (std.mem.indexOfScalar(u8, v, '=')) |eq| {
                var keys: std.ArrayList([]const u8) = .empty;
                var it = std.mem.splitScalar(u8, v[eq + 1 ..], ',');
                while (it.next()) |k| if (k.len > 0) try keys.append(ctx.a, k);
                try p.subjects.append(ctx.a, .{ .subject = v[0..eq], .keys = keys.items });
            } else try p.subjects.append(ctx.a, .{ .subject = v, .keys = null });
        } else if (std.mem.eql(u8, x, "--context")) {
            try p.contexts.append(ctx.a, v);
        } else if (std.mem.eql(u8, x, "--domain")) {
            p.domain = v;
        } else if (std.mem.eql(u8, x, "--keys")) {
            var keys: std.ArrayList([]const u8) = .empty;
            var it = std.mem.splitScalar(u8, v, ',');
            while (it.next()) |k| if (k.len > 0) try keys.append(ctx.a, k);
            p.keys = keys.items;
        } else {
            p.bad = x;
            return p;
        }
    }
    if (p.repairs.items.len > 0) p.record.repair = p.repairs.items;
    if (p.actions.items.len > 0) p.record.actions = p.actions.items;
    return p;
}

fn messageArgs(ctx: *Ctx, p: *Parsed, from: usize) ![]const Value {
    // --details' args, when given, are the arguments (they can carry [MESSAGE, ARG...] for a message with arguments)
    if (p.record.args.len > 0) return p.record.args;
    var list: std.ArrayList(Value) = .empty;
    if (p.positional.items.len > from) {
        for (p.positional.items[from..]) |x| try list.append(ctx.a, .{ .string = x });
    }
    return list.items;
}

fn printList(ctx: *Ctx, p: *Parsed) !u8 {
    const pkg: ?[]const u8 = if (p.positional.items.len > 0) p.positional.items[0] else null;
    if (p.json) {
        const out = try engine.listJson(ctx, pkg, p.lang);
        _ = engine.writeAll(1, out);
        return 0;
    }
    const items = try engine.collect(ctx, pkg);
    var out: std.ArrayList(u8) = .empty;
    const none = try engine.render(ctx, engine.engine_package, "LOCAL27", &.{}, p.lang);
    if (items.len == 0) {
        try out.appendSlice(ctx.a, none.text);
        try out.append(ctx.a, '\n');
    }
    for (items) |item| {
        const r = item.record orelse {
            const e = try engine.render(ctx, engine.engine_package, "LOCAL25", &.{.{ .string = item.unreadable }}, p.lang);
            try out.print(ctx.a, "{s}  {s}\n  {s}\n\n", .{ @tagName(item.scope), item.file, e.text });
            continue;
        };
        const shown = try engine.renderRecord(ctx, r, p.lang);
        const since = try engine.render(ctx, engine.engine_package, "LOCAL22", &.{.{ .string = r.first }}, shown.lang);
        try out.print(ctx.a, "{s}  {s}  {s}  {s}  ({s})", .{ @tagName(r.severity), @tagName(item.scope), r.package, r.key, since.text });
        if (item.hidden) {
            const h = try engine.render(ctx, engine.engine_package, "LOCAL24", &.{}, shown.lang);
            try out.print(ctx.a, "  [{s}]", .{h.text});
        }
        try out.print(ctx.a, "\n  {s}\n", .{shown.title});
        var lines = std.mem.splitScalar(u8, shown.text, '\n');
        while (lines.next()) |l| try out.print(ctx.a, "  {s}\n", .{l});
        for (r.repair) |cmd| {
            const rp = try engine.render(ctx, engine.engine_package, "LOCAL23", &.{.{ .string = try std.mem.join(ctx.a, " ", cmd) }}, shown.lang);
            try out.print(ctx.a, "  {s}\n", .{rp.text});
        }
        try out.appendSlice(ctx.a, "\n");
    }
    _ = engine.writeAll(1, out.items);
    return 0;
}

fn runMain(ctx: *Ctx, argv: []const []const u8) !u8 {
    if (argv.len < 1) return wrongUse(ctx, "LOCAL52", &.{});
    const verb = argv[0];
    if (std.mem.eql(u8, verb, "--version")) {
        _ = engine.writeAll(1, "sparky-stereo-problems " ++ engine.version ++ "\n");
        return 0;
    }
    if (std.mem.eql(u8, verb, "--help") or std.mem.eql(u8, verb, "help")) {
        _ = engine.writeAll(1, try usageText(ctx));
        return 0;
    }
    var p = try parse(ctx, argv[1..]);
    if (p.bad) |b| return wrongUse(ctx, "LOCAL54", &.{b});
    const pos = p.positional.items;
    const scope = p.scope orelse engine.defaultScope(ctx);
    // pkexec runs only a repair of what root kept, never anything the caller names (org.sparkylinux.sparkystereo.problems.repair)
    if (ctx.under_pkexec and (!std.mem.eql(u8, verb, "repair") or p.scope == null or p.scope.? == .person)) {
        return wrongUse(ctx, "LOCAL55", &.{});
    }
    if (std.mem.eql(u8, verb, "keep") or std.mem.eql(u8, verb, "run")) {
        if (pos.len < 3) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE KEY MESSAGE"});
        var r = p.record;
        r.package = pos[0];
        r.key = pos[1];
        r.message = pos[2];
        r.args = try messageArgs(ctx, &p, 3);
        if (std.mem.eql(u8, verb, "keep")) {
            const kept = engine.keep(ctx, scope, r) catch |e| {
                if (e == error.Failed) {
                    _ = said(ctx);
                    journalNote(ctx);
                    return 1;
                }
                return e;
            };
            if (!p.quiet) try sayRecord(ctx, kept);
            journalNote(ctx);
            return 0;
        }
        const command = p.command orelse return wrongUse(ctx, "LOCAL57", &.{});
        if (command.len == 0) return wrongUse(ctx, "LOCAL57", &.{});
        const status = engine.run(ctx, scope, r, command) catch |e| {
            if (e == error.Failed) {
                _ = said(ctx);
                journalNote(ctx);
                return 1;
            }
            return e;
        };
        if (status != 0 and !p.quiet) {
            for (try engine.collect(ctx, r.package)) |item| {
                if (item.record) |k| if (item.scope == scope and std.mem.eql(u8, k.key, r.key)) try sayRecord(ctx, k);
            }
        }
        journalNote(ctx);
        return @intCast(@min(@max(status, 0), 255));
    }
    if (std.mem.eql(u8, verb, "clear") and p.all) {
        if (pos.len != 1) return wrongUse(ctx, "LOCAL53", &.{"--all PACKAGE"});
        _ = engine.clearAll(ctx, pos[0]) catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        };
        journalNote(ctx);
        return 0;
    }
    if (std.mem.eql(u8, verb, "clear")) {
        if (pos.len != 2) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE KEY"});
        _ = engine.clear(ctx, scope, pos[0], pos[1]) catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        };
        journalNote(ctx);
        return 0;
    }
    if (std.mem.eql(u8, verb, "say")) {
        if (pos.len < 2) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE MESSAGE"});
        var list: std.ArrayList(Value) = .empty;
        for (pos[2..]) |x| try list.append(ctx.a, .{ .string = x });
        const both = engine.say(ctx, pos[0], pos[1], list.items) catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        };
        err(try std.mem.concat(ctx.a, u8, &.{ pos[0], ": ", both[0].text, "\n" }));
        if (!std.mem.eql(u8, both[0].lang, "en")) err(try std.mem.concat(ctx.a, u8, &.{ pos[0], ": (en) ", both[1].text, "\n" }));
        journalNote(ctx);
        return 0;
    }
    if (std.mem.eql(u8, verb, "list")) {
        if (pos.len > 1) return wrongUse(ctx, "LOCAL58", &.{});
        return printList(ctx, &p);
    }
    if (std.mem.eql(u8, verb, "repair")) {
        if (pos.len < 1 or pos.len > 2) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE [KEY]"});
        var keys: std.ArrayList([]const u8) = .empty;
        if (pos.len == 2) {
            try keys.append(ctx.a, pos[1]);
        } else {
            for (try engine.collect(ctx, pos[0])) |item| {
                if (item.record) |r| if (item.scope == scope) try keys.append(ctx.a, r.key);
            }
            if (keys.items.len == 0) {
                engine.setErr(ctx, "LOCAL18", &.{ "*", pos[0] }) catch {};
                return said(ctx);
            }
        }
        var worst: u8 = 0;
        for (keys.items) |k| {
            const status = engine.repair(ctx, scope, pos[0], k) catch |e| {
                if (e == error.Failed) {
                    worst = 1;
                    _ = said(ctx);
                    continue;
                }
                return e;
            };
            if (status != 0) {
                _ = said(ctx);
                worst = @intCast(@min(@max(status, 1), 255));
            }
        }
        journalNote(ctx);
        return worst;
    }
    if (std.mem.eql(u8, verb, "hide") or std.mem.eql(u8, verb, "show")) {
        if (pos.len != 2) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE KEY"});
        const done = if (std.mem.eql(u8, verb, "hide")) engine.hide(ctx, scope, pos[0], pos[1]) else engine.show(ctx, scope, pos[0], pos[1]);
        done catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        };
        journalNote(ctx);
        return 0;
    }
    if (std.mem.eql(u8, verb, "catalog")) {
        if (pos.len != 3) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE DIR OUTDIR"});
        const n = engine.buildCatalog(ctx, pos[0], pos[1], pos[2], p.subjects.items, p.keys, p.contexts.items, p.domain) catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        };
        _ = engine.writeAll(1, try std.fmt.allocPrint(ctx.a, "{s}: {d} catalog entries in {s}\n", .{ pos[0], n, pos[2] }));
        return 0;
    }
    if (std.mem.eql(u8, verb, "service-failed")) {
        _ = engine.serviceFailed(ctx, if (pos.len > 0) pos[0] else null) catch |e| {
            if (e == error.Failed) {
                _ = said(ctx);
                journalNote(ctx);
                return 1;
            }
            return e;
        };
        journalNote(ctx);
        return 0;
    }
    if (std.mem.eql(u8, verb, "text")) {
        // a shell caller's way to say one kept problem (cushion-swap's status)
        if (pos.len != 2) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE KEY"});
        switch (engine.get(ctx, scope, pos[0], pos[1]) catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        }) {
            .record => |r| {
                const shown = try engine.renderRecord(ctx, r, p.lang);
                _ = engine.writeAll(1, try std.mem.concat(ctx.a, u8, &.{ shown.text, "\n" }));
                return 0;
            },
            .unreadable => |e| {
                engine.setErr(ctx, "LOCAL25", &.{e}) catch {};
                return said(ctx);
            },
            .missing => {
                engine.setErr(ctx, "LOCAL18", &.{ pos[1], pos[0] }) catch {};
                return said(ctx);
            },
        }
    }
    if (std.mem.eql(u8, verb, "message-id")) {
        if (pos.len != 2) return wrongUse(ctx, "LOCAL53", &.{"PACKAGE MESSAGE"});
        _ = engine.writeAll(1, try std.mem.concat(ctx.a, u8, &.{ try engine.messageId(ctx.a, pos[0], pos[1]), "\n" }));
        return 0;
    }
    if (std.mem.eql(u8, verb, "languages")) {
        const langs = try engine.languages(ctx);
        _ = engine.writeAll(1, try std.mem.concat(ctx.a, u8, &.{ try std.mem.join(ctx.a, ":", langs), if (langs.len > 0) ":en\n" else "en\n" }));
        return 0;
    }
    return wrongUse(ctx, "LOCAL56", &.{verb});
}

pub export fn main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var args = a.alloc([]const u8, @intCast(@max(argc - 1, 0))) catch return 1;
    var i: usize = 1;
    while (i < @as(usize, @intCast(argc))) : (i += 1) args[i - 1] = std.mem.span(argv[i]);
    var ctx = Ctx.init(a);
    defer ctx.deinit();
    const status = runMain(&ctx, args) catch {
        err("sparky-stereo-problems: out of memory (the engine could not allocate memory)\n");
        return 1;
    };
    return status;
}
