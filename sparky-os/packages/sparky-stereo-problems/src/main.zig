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

const usage =
    \\Usage: sparky-stereo-problems COMMAND ...
    \\  keep [SCOPE] [OPTIONS] PACKAGE KEY MESSAGE [ARG...]
    \\        keeps a problem until it is repaired, and says it in the journal
    \\  run [SCOPE] [OPTIONS] PACKAGE KEY MESSAGE [ARG...] -- COMMAND [ARG...]
    \\        runs COMMAND with its output shown; a success clears KEY, a failure keeps it with the command, its exit
    \\        status and the end of its output (MESSAGE's first two %s are the command and its status, then ARGs);
    \\        exits with COMMAND's status
    \\  clear [SCOPE] PACKAGE KEY              the step works again
    \\  say PACKAGE MESSAGE [ARG...]          says a notice on standard error and in the journal, kept nowhere
    \\  list [--json] [--lang LANGUAGES] [PACKAGE]
    \\  repair [SCOPE] PACKAGE [KEY]          runs the repair commands of KEY (of every problem of PACKAGE)
    \\  hide [SCOPE] PACKAGE KEY              hides it from your notifications until it changes or a repair fails
    \\  show [SCOPE] PACKAGE KEY              shows it again
    \\  catalog PACKAGE LANGDIR OUTDIR [--subject KEY[=MESSAGE,...]]... [--keys MESSAGE,...]
    \\        builds PACKAGE.catalog and PACKAGE.LANG.catalog (journal message catalogs) from Sparky language files
    \\  service-failed [UNIT]                 the handler of a failed system service (sparky-stereo-problems-failed@)
    \\  message-id PACKAGE MESSAGE | languages | --version
    \\SCOPE: --machine (the default for root), --boot (this boot only), --person (the default for a person)
    \\OPTIONS: --severity failed|degraded|notice  --repair JSON-ARRAY (repeatable)  --command JSON-ARRAY  --status N
    \\  --output TEXT  --output-file FILE  --action '{"id":..,"label":[MESSAGE,ARG...],"command":[..]}' (repeatable)
    \\  --unit UNIT  --details JSON-OBJECT
    \\An ARG written @KEY is the package's own message KEY, in the same language.
    \\Exit status: 0 done, 1 failed (said), 2 wrong use; run exits with COMMAND's status, repair with the failing one's.
    \\
;

fn err(text: []const u8) void {
    _ = engine.writeAll(2, text);
}

fn wrongUse(what: []const u8) u8 {
    err("sparky-stereo-problems: ");
    err(what);
    err("\n");
    err(usage);
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
        const shown = try engine.render(ctx, r.package, r.message, r.args, p.lang);
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
    if (argv.len < 1) return wrongUse("a command is needed");
    const verb = argv[0];
    if (std.mem.eql(u8, verb, "--version")) {
        _ = engine.writeAll(1, "sparky-stereo-problems " ++ engine.version ++ "\n");
        return 0;
    }
    if (std.mem.eql(u8, verb, "--help") or std.mem.eql(u8, verb, "help")) {
        _ = engine.writeAll(1, usage);
        return 0;
    }
    var p = try parse(ctx, argv[1..]);
    if (p.bad) |b| return wrongUse(try std.mem.concat(ctx.a, u8, &.{ "wrong or missing value for ", b }));
    const pos = p.positional.items;
    const scope = p.scope orelse engine.defaultScope(ctx);
    // pkexec runs only a repair of what root kept, never anything the caller names (org.sparkylinux.problems.repair)
    if (ctx.under_pkexec and (!std.mem.eql(u8, verb, "repair") or p.scope == null or p.scope.? == .person)) {
        return wrongUse("through pkexec only repair --machine or repair --boot runs");
    }
    if (std.mem.eql(u8, verb, "keep") or std.mem.eql(u8, verb, "run")) {
        if (pos.len < 3) return wrongUse("PACKAGE KEY MESSAGE are needed");
        var r = p.record;
        r.package = pos[0];
        r.key = pos[1];
        r.message = pos[2];
        r.args = try messageArgs(ctx, &p, 3);
        if (std.mem.eql(u8, verb, "keep")) {
            _ = engine.keep(ctx, scope, r) catch |e| {
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
        const command = p.command orelse return wrongUse("run needs -- COMMAND");
        if (command.len == 0) return wrongUse("run needs -- COMMAND");
        const status = engine.run(ctx, scope, r, command) catch |e| {
            if (e == error.Failed) {
                _ = said(ctx);
                journalNote(ctx);
                return 1;
            }
            return e;
        };
        journalNote(ctx);
        return @intCast(@min(@max(status, 0), 255));
    }
    if (std.mem.eql(u8, verb, "clear")) {
        if (pos.len != 2) return wrongUse("PACKAGE KEY are needed");
        _ = engine.clear(ctx, scope, pos[0], pos[1]) catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        };
        journalNote(ctx);
        return 0;
    }
    if (std.mem.eql(u8, verb, "say")) {
        if (pos.len < 2) return wrongUse("PACKAGE MESSAGE are needed");
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
        if (pos.len > 1) return wrongUse("list takes one PACKAGE at most");
        return printList(ctx, &p);
    }
    if (std.mem.eql(u8, verb, "repair")) {
        if (pos.len < 1 or pos.len > 2) return wrongUse("PACKAGE [KEY] are needed");
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
        if (pos.len != 2) return wrongUse("PACKAGE KEY are needed");
        const done = if (std.mem.eql(u8, verb, "hide")) engine.hide(ctx, scope, pos[0], pos[1]) else engine.show(ctx, scope, pos[0], pos[1]);
        done catch |e| {
            if (e == error.Failed) return said(ctx);
            return e;
        };
        journalNote(ctx);
        return 0;
    }
    if (std.mem.eql(u8, verb, "catalog")) {
        if (pos.len != 3) return wrongUse("PACKAGE LANGDIR OUTDIR are needed");
        const n = engine.buildCatalog(ctx, pos[0], pos[1], pos[2], p.subjects.items, p.keys) catch |e| {
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
    if (std.mem.eql(u8, verb, "message-id")) {
        if (pos.len != 2) return wrongUse("PACKAGE MESSAGE are needed");
        _ = engine.writeAll(1, try std.mem.concat(ctx.a, u8, &.{ try engine.messageId(ctx.a, pos[0], pos[1]), "\n" }));
        return 0;
    }
    if (std.mem.eql(u8, verb, "languages")) {
        const langs = try engine.languages(ctx);
        _ = engine.writeAll(1, try std.mem.concat(ctx.a, u8, &.{ try std.mem.join(ctx.a, ":", langs), if (langs.len > 0) ":en\n" else "en\n" }));
        return 0;
    }
    return wrongUse(try std.mem.concat(ctx.a, u8, &.{ "unknown command ", verb }));
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
        err("sparky-stereo-problems: out of memory\n");
        return 1;
    };
    return status;
}
