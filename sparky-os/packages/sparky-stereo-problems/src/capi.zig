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

fn plainError(text: []const u8) c_int {
    copyTo(&err_local, text);
    copyTo(&err_en, text);
    have_err = true;
    return 2;
}

fn result(ctx: *engine.Ctx, e: anyerror) c_int {
    if (e == error.Failed) {
        keepError(ctx);
        return 1;
    }
    return plainError("out of memory");
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

fn strings(a: std.mem.Allocator, list: ?[*]const ?[*:0]const u8, n: c_int) ?[]const []const u8 {
    if (n < 0) return null;
    const count: usize = @intCast(n);
    const out = a.alloc([]const u8, count) catch return null;
    for (0..count) |i| out[i] = std.mem.span((list orelse return null)[i] orelse return null);
    return out;
}

fn values(a: std.mem.Allocator, list: ?[*]const ?[*:0]const u8, n: c_int) ?[]const Value {
    const s = strings(a, list, n) orelse return null;
    const out = a.alloc(Value, s.len) catch return null;
    for (s, 0..) |x, i| out[i] = .{ .string = x };
    return out;
}

fn dup(s: []const u8) ?[*:0]u8 {
    const p: [*]u8 = @ptrCast(sys.malloc(s.len + 1) orelse return null);
    @memcpy(p[0..s.len], s);
    p[s.len] = 0;
    return @ptrCast(p);
}

fn record(c: *Call, package: ?[*:0]const u8, key: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int, details: ?[*:0]const u8) ?engine.Record {
    const a = c.arena.allocator();
    var r = engine.Record{
        .package = str(package) orelse return null,
        .key = str(key) orelse return null,
        .message = str(message) orelse return null,
        .args = values(a, args, nargs) orelse return null,
    };
    if (str(details)) |d| {
        const v = std.json.parseFromSliceLeaky(Value, a, d, .{}) catch return null;
        if (v != .object) return null;
        engine.applyDetails(a, &r, v.object) catch return null;
    }
    return r;
}

export fn ssp_keep(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int, details: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return plainError("unknown scope");
    const r = record(&c, package, key, message, args, nargs, details) orelse return plainError("wrong arguments or details");
    _ = engine.keep(&c.ctx, s, r) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_run(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int, command: ?[*]const ?[*:0]const u8, ncommand: c_int, details: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return -1;
    const r = record(&c, package, key, message, args, nargs, details) orelse return -1;
    const cmd = strings(c.arena.allocator(), command, ncommand) orelse return -1;
    if (cmd.len == 0) return -1;
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
    const s = scopeOf(&c.ctx, scope) orelse return plainError("unknown scope");
    _ = engine.clear(&c.ctx, s, str(package) orelse return 2, str(key) orelse return 2) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_clear_all(package: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    _ = engine.clearAll(&c.ctx, str(package) orelse return 2) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_say(package: ?[*:0]const u8, message: ?[*:0]const u8, args: ?[*]const ?[*:0]const u8, nargs: c_int) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const a = c.arena.allocator();
    const pkg = str(package) orelse return 2;
    const both = engine.say(&c.ctx, pkg, str(message) orelse return 2, values(a, args, nargs) orelse return 2) catch |e| return result(&c.ctx, e);
    const line = std.mem.concat(a, u8, &.{ pkg, ": ", both[0].text, "\n" }) catch return 2;
    _ = engine.writeAll(2, line);
    if (!std.mem.eql(u8, both[0].lang, "en")) {
        _ = engine.writeAll(2, std.mem.concat(a, u8, &.{ pkg, ": (en) ", both[1].text, "\n" }) catch return 2);
    }
    return 0;
}

export fn ssp_repair(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return -1;
    const status = engine.repair(&c.ctx, s, str(package) orelse return -1, str(key) orelse return -1) catch |e| {
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
    const s = scopeOf(&c.ctx, scope) orelse return plainError("unknown scope");
    engine.hide(&c.ctx, s, str(package) orelse return 2, str(key) orelse return 2) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_show(scope: c_int, package: ?[*:0]const u8, key: ?[*:0]const u8) c_int {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const s = scopeOf(&c.ctx, scope) orelse return plainError("unknown scope");
    engine.show(&c.ctx, s, str(package) orelse return 2, str(key) orelse return 2) catch |e| return result(&c.ctx, e);
    return 0;
}

export fn ssp_list_json(package: ?[*:0]const u8, lang: ?[*:0]const u8) ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const out = engine.listJson(&c.ctx, str(package), str(lang)) catch |e| {
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
    const r = engine.render(&c.ctx, str(package) orelse return null, str(message) orelse return null, values(a, args, nargs) orelse return null, str(lang)) catch |e| {
        _ = result(&c.ctx, e);
        return null;
    };
    const text = std.json.Stringify.valueAlloc(a, .{ .title = r.title, .text = r.text, .lang = r.lang }, .{}) catch return null;
    return dup(text);
}

export fn ssp_message_id(package: ?[*:0]const u8, message: ?[*:0]const u8) ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const id = engine.messageId(c.arena.allocator(), str(package) orelse return null, str(message) orelse return null) catch return null;
    return dup(id);
}

export fn ssp_languages() ?[*:0]u8 {
    var c: Call = undefined;
    begin(&c);
    defer c.deinit();
    const langs = engine.languages(&c.ctx) catch return null;
    const joined = std.mem.join(c.arena.allocator(), ":", langs) catch return null;
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
