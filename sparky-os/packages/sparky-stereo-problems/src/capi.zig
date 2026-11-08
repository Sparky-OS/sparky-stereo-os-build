// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// libsparky-stereo-problems: the engine for C, C++ and Python (include/sparky-stereo-problems.h says what each call
// does). Every call is whole by itself: no state is kept between calls but the text of the last failure, per thread.

const std = @import("std");
const engine = @import("engine.zig");
const sys = @import("sys.zig");

const Value = std.json.Value;

threadlocal var err_local: [4096]u8 = undefined;
threadlocal var err_en: [4096]u8 = undefined;
threadlocal var have_err = false;

const Call = struct {
    arena: std.heap.ArenaAllocator,
    ctx: engine.Ctx,

    fn deinit(c: *Call) void {
        c.ctx.deinit();
        c.arena.deinit();
    }
};

fn begin(c: *Call) void {
    c.arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    c.ctx = engine.Ctx.init(c.arena.allocator());
    have_err = false;
}

fn copyTo(buf: []u8, s: []const u8) void {
    const n = @min(s.len, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    buf[n] = 0;
}

fn keepError(ctx: *engine.Ctx) void {
    copyTo(&err_local, ctx.err_local);
    copyTo(&err_en, ctx.err_en);
    have_err = true;
}

// an allocation failed: LOCAL64 in the person's language and in English, rendered with memory of its own
fn outOfMemory() c_int {
    _ = engine.outOfMemory(&err_local, &err_en);
    have_err = true;
    return 2;
}

// a wrong call (LOCAL65 a scope that is none, LOCAL66 a missing name or arguments the library cannot read): said like
// every failure, from the engine's catalog
fn wrongCall(ctx: *engine.Ctx, msg: []const u8) c_int {
    engine.setErr(ctx, msg, &.{}) catch return outOfMemory();
    keepError(ctx);
    return 2;
}

const CallError = error{ Wrong, OutOfMemory };

fn callFailed(ctx: *engine.Ctx, e: CallError) c_int {
    return switch (e) {
        error.Wrong => wrongCall(ctx, "LOCAL66"),
        error.OutOfMemory => outOfMemory(),
    };
}

// a call that returns text: null, said
fn failedNull(ctx: *engine.Ctx, e: CallError) ?[*:0]u8 {
    _ = callFailed(ctx, e);
    return null;
}

fn result(ctx: *engine.Ctx, e: anyerror) c_int {
    if (e == error.Failed) {
        keepError(ctx);
        return 1;
    }
    return outOfMemory();
}

fn scopeOf(ctx: *engine.Ctx, s: c_int) ?engine.Scope {
    return switch (s) {
        -1 => engine.defaultScope(ctx),
        0 => .machine,
        1 => .boot,
        2 => .person,
        else => null,
    };
}

fn str(p: ?[*:0]const u8) ?[]const u8 {
    return if (p) |x| std.mem.span(x) else null;
}

// a name the call must give
fn name(p: ?[*:0]const u8) CallError![]const u8 {
    return str(p) orelse error.Wrong;
}

fn strings(a: std.mem.Allocator, list: ?[*]const ?[*:0]const u8, n: c_int) CallError![]const []const u8 {
    if (n < 0) return error.Wrong;
    const count: usize = @intCast(n);
    const out = try a.alloc([]const u8, count);
    for (0..count) |i| out[i] = std.mem.span((list orelse return error.Wrong)[i] orelse return error.Wrong);
    return out;
}

fn values(a: std.mem.Allocator, list: ?[*]const ?[*:0]const u8, n: c_int) CallError![]const Value {
    const s = try strings(a, list, n);
    const out = try a.alloc(Value, s.len);
    for (s, 0..) |x, i| out[i] = .{ .string = x };
    return out;
}

// text the caller frees with ssp_free; null, said, when it cannot be allocated
fn dup(s: []const u8) ?[*:0]u8 {
    const p: [*]u8 = @ptrCast(sys.malloc(s.len + 1) orelse {
        _ = outOfMemory();
        return null;
    });
    @memcpy(p[0..s.len], s);
    p[s.len] = 0;
    return @ptrCast(p);
}

fn record(c: *Call, package: ?[*:0]const u8, key: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int, details: ?[*:0]const u8) CallError!engine.Record {
    const a = c.arena.allocator();
    var r = engine.Record{
        .package = try name(package),
        .key = try name(key),
        .message = try name(message),
        .args = try values(a, args, nargs),
    };
    if (str(details)) |d| {
        const v = std.json.parseFromSliceLeaky(Value, a, d, .{}) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else error.Wrong;
        if (v != .object) return error.Wrong;
        engine.applyDetails(a, &r, v.object) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else error.Wrong;
    }
    return r;
}

export fn ssp_keep(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int, details: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return wrongCall(&c.ctx, "LOCAL65");
    const r = record(&c, package, key, message, args, nargs, details) catch |e| return callFailed(&c.ctx, e);
    _ = engine.keep(&c.ctx, s, r) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_run(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int, command: ?[*]const ?[*:0]const u8, ncommand: c_int, details: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse {
        _ = wrongCall(&c.ctx, "LOCAL65");
        return -1;
    };
    const r = record(&c, package, key, message, args, nargs, details) catch |e| {
        _ = callFailed(&c.ctx, e);
        return -1;
    };
    const cmd = strings(c.arena.allocator(), command, ncommand) catch |e| {
        _ = callFailed(&c.ctx, e);
        return -1;
    };
    if (cmd.len == 0) {
        _ = wrongCall(&c.ctx, "LOCAL66");
        return -1;
    }
    const status = engine.run(&c.ctx, s, r, cmd) catch |e| {
        _ = result(&c.ctx, e);
        return -1;
    };
    return @intCast(status);
}

export fn ssp_clear(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return wrongCall(&c.ctx, "LOCAL65");
    _ = engine.clear(&c.ctx, s, name(package) catch |e| return callFailed(&c.ctx, e), name(key) catch |e| return callFailed(&c.ctx, e)) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_clear_all(package: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    _ = engine.clearAll(&c.ctx, name(package) catch |e| return callFailed(&c.ctx, e)) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_say(package: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const a = c.arena.allocator();
    const pkg = name(package) catch |e| return callFailed(&c.ctx, e);
    const msg = name(message) catch |e| return callFailed(&c.ctx, e);
    const vals = values(a, args, nargs) catch |e| return callFailed(&c.ctx, e);
    const both = engine.say(&c.ctx, pkg, msg, vals) catch |e| return result(&c.ctx, e);
    const line = std.mem.concat(a, u8, &.{ pkg, ": ", both[0].text, "\n" }) catch return outOfMemory();
    _ = engine.writeAll(2, line);
    if (!std.mem.eql(u8, both[0].lang, "en")) {
        _ = engine.writeAll(2, std.mem.concat(a, u8, &.{ pkg, ": (en) ", both[1].text, "\n" }) catch return outOfMemory());
    }
    return 0;
}

export fn ssp_repair(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse {
        _ = wrongCall(&c.ctx, "LOCAL65");
        return -1;
    };
    const pkg = name(package) catch |e| {
        _ = callFailed(&c.ctx, e);
        return -1;
    };
    const k = name(key) catch |e| {
        _ = callFailed(&c.ctx, e);
        return -1;
    };
    const status = engine.repair(&c.ctx, s, pkg, k) catch |e| {
        _ = result(&c.ctx, e);
        return -1;
    };
    if (status != 0) keepError(&c.ctx);
    return @intCast(status);
}

export fn ssp_hide(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return wrongCall(&c.ctx, "LOCAL65");
    engine.hide(&c.ctx, s, name(package) catch |e| return callFailed(&c.ctx, e), name(key) catch |e| return callFailed(&c.ctx, e)) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_show(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return wrongCall(&c.ctx, "LOCAL65");
    engine.show(&c.ctx, s, name(package) catch |e| return callFailed(&c.ctx, e), name(key) catch |e| return callFailed(&c.ctx, e)) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_list_json(package: ?[*:0]const u8, lang: ?[*:0]const u8) ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const out = engine.listJson(&c.ctx, str(package), str(lang), false) catch |e| {
        _ = result(&c.ctx, e);
        return null;
    };
    return dup(out);
}

export fn ssp_list_over_json(package: ?[*:0]const u8, lang: ?[*:0]const u8) ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const out = engine.listJson(&c.ctx, str(package), str(lang), true) catch |e| {
        _ = result(&c.ctx, e);
        return null;
    };
    return dup(out);
}

export fn ssp_render(package: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int, lang: ?[*:0]const u8) ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const a = c.arena.allocator();
    const pkg = name(package) catch |e| return failedNull(&c.ctx, e);
    const msg = name(message) catch |e| return failedNull(&c.ctx, e);
    const vals = values(a, args, nargs) catch |e| return failedNull(&c.ctx, e);
    const r = engine.render(&c.ctx, pkg, msg, vals, str(lang)) catch |e| {
        _ = result(&c.ctx, e);
        return null;
    };
    const text = std.json.Stringify.valueAlloc(a, .{ .title = r.title, .text = r.text, .lang = r.lang }, .{}) catch return failedNull(&c.ctx, error.OutOfMemory);
    return dup(text);
}

export fn ssp_message_id(package: ?[*:0]const u8, message: ?[*:0]const u8) ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const pkg = name(package) catch |e| return failedNull(&c.ctx, e);
    const msg = name(message) catch |e| return failedNull(&c.ctx, e);
    const id = engine.messageId(c.arena.allocator(), pkg, msg) catch return failedNull(&c.ctx, error.OutOfMemory);
    return dup(id);
}

export fn ssp_languages() ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const langs = engine.languages(&c.ctx) catch return failedNull(&c.ctx, error.OutOfMemory);
    const joined = std.mem.join(c.arena.allocator(), ":", langs) catch return failedNull(&c.ctx, error.OutOfMemory);
    return dup(joined);
}

export fn ssp_error() [*:0]const u8 {
    if (!have_err) return "";
    return @ptrCast(&err_local);
}

export fn ssp_error_en() [*:0]const u8 {
    if (!have_err) return "";
    return @ptrCast(&err_en);
}

export fn ssp_free(p: ?*anyopaque) void {
    sys.free(p);
}
