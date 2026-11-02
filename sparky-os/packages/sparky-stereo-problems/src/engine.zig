// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// sparky-stereo-problems: the one place where a step of the edition that cannot do what it is for keeps what failed,
// why and what to do, until it is repaired (ORDER 350; Daniel, 2026-11-01: "nothing we do should silently fail or have
// a fall back - either it works or not and the user must know").
//
// One record per file in a flat store, written through a dot-file and renamed, under a flock of the store's .lock:
//   /var/lib/sparky-stereo-problems         the machine's, kept until repaired
//   /run/sparky-stereo-problems             this boot's (a failed system service)
//   $XDG_STATE_HOME/sparky-stereo-problems  the person's own
// A record's file is PACKAGE_KEY.json (KEY with every byte outside [A-Za-z0-9._@:+-] written as %XX).
//
// Messages are the package's own translations, built at package build time into journal message catalogs
// (/usr/lib/systemd/catalog/PACKAGE[.LANG].catalog, so `journalctl -x` explains each problem too). The engine reads
// them itself in gettext's order (LANGUAGE, LC_ALL, LC_MESSAGES, LANG, then /etc/default/locale; LANGUAGE is not used
// in the C locale, as gettext does), the whole name, the bare language, then English; Chinese keeps its script. A
// message's MESSAGE_ID is the name-based UUID (RFC 9562 version 5, URL namespace) of
// https://sparkylinux.org/problems/PACKAGE/KEY. Every event is mirrored to the journal with that MESSAGE_ID.
//
// Hide is the person's: it keeps the problem listed and hidden with its evidence, in the person's own state
// ($XDG_STATE_HOME/sparky-stereo-problems/.hidden), and it holds only while the problem keeps its message and no
// repair failed since (the record's id and generation); Show undoes it.

const std = @import("std");
const sys = @import("sys.zig");

const Allocator = std.mem.Allocator;
const Value = std.json.Value;

pub const version = "0.1.0";
pub const engine_package = "sparky-stereo-problems";
const support_url = "https://github.com/Sparky-OS/sparky-stereo-os/issues";
const output_lines = 200;
const output_bytes = 65536;

pub const Scope = enum {
    machine,
    boot,
    person,

    pub fn parse(text: []const u8) ?Scope {
        return std.meta.stringToEnum(Scope, text);
    }
};

pub const Severity = enum {
    failed,
    degraded,
    notice,

    pub fn parse(text: []const u8) ?Severity {
        return std.meta.stringToEnum(Severity, text);
    }

    fn priority(s: Severity) []const u8 {
        return switch (s) {
            .failed => "3",
            .degraded => "4",
            .notice => "5",
        };
    }
};

pub const Action = struct {
    id: []const u8,
    // a message of the record's package and its arguments: [KEY, ARG...]
    label: []const Value,
    command: []const []const u8,
};

pub const Repair = struct {
    time: []const u8,
    command: []const []const u8,
    status: i64,
    output: []const u8,
};

pub const Record = struct {
    package: []const u8,
    key: []const u8,
    message: []const u8,
    // each a string (an "@KEY" string is that message of the package) or [KEY, ARG...], a message with its arguments
    args: []const Value = &.{},
    severity: Severity = .failed,
    id: []const u8 = "",
    generation: i64 = 0,
    first: []const u8 = "",
    time: []const u8 = "",
    changed: []const u8 = "",
    command: ?[]const []const u8 = null,
    status: ?i64 = null,
    output: []const u8 = "",
    repair: []const []const []const u8 = &.{},
    actions: []const Action = &.{},
    unit: ?[]const u8 = null,
    repairs_failed: i64 = 0,
    last_repair: ?Repair = null,
    // further sentences after the message, each "@KEY" or [KEY, ARG...] of the package (a reason, what to do)
    more: []const Value = &.{},
    // the English text rendered when the problem was kept: shown when no catalog has the message any more
    text_en: []const u8 = "",
    // the package's own fields, kept and returned as they are
    data: ?Value = null,
    // when it was last kept, in nanoseconds: a repair command that keeps it again is told from one that repaired it
    kept_ns: i64 = 0,
};

pub const Rendered = struct {
    title: []const u8,
    text: []const u8,
    lang: []const u8,
    // false when no catalog has the message (then the text names it with its arguments)
    found: bool = true,
};

const Entry = struct {
    subject: []const u8,
    body: []const u8,
};
const Catalog = std.StringHashMapUnmanaged(Entry);

pub const Failure = error{ Failed, OutOfMemory };

pub const Ctx = struct {
    a: Allocator,
    root: []const u8 = "",
    // folders searched in order; SPARKY_STEREO_PROBLEMS_CATALOG may name several, separated by ":"
    catalog_dir: []const u8 = "/usr/lib/systemd/catalog",
    euid: u32,
    under_pkexec: bool = false,
    // the last failure, in English (for support and the journal) and in the person's language
    err_en: []const u8 = "",
    err_local: []const u8 = "",
    err_lang: []const u8 = "en",
    journal_error: ?[]const u8 = null,
    catalogs: std.StringHashMapUnmanaged(?Catalog) = .empty,
    langs: ?[]const []const u8 = null,
    bus: ?*anyopaque = null,
    bus_tried: bool = false,

    pub fn init(a: Allocator) Ctx {
        var ctx = Ctx{ .a = a, .euid = sys.geteuid() };
        // under pkexec only what root kept is read: the caller's environment never names the stores
        ctx.under_pkexec = ctx.euid == 0 and sys.getenv("PKEXEC_UID") != null;
        if (!ctx.under_pkexec) {
            if (env("SPARKY_STEREO_ROOT")) |r| ctx.root = r;
            if (env("SPARKY_STEREO_PROBLEMS_CATALOG")) |c| ctx.catalog_dir = c;
        }
        return ctx;
    }

    pub fn deinit(ctx: *Ctx) void {
        if (ctx.bus) |b| _ = sys.sd_bus_flush_close_unref(b);
        ctx.bus = null;
    }
};

pub fn env(name: [*:0]const u8) ?[]const u8 {
    const v = sys.getenv(name) orelse return null;
    const s = std.mem.span(v);
    return if (s.len == 0) null else s;
}

fn z(a: Allocator, s: []const u8) Failure![:0]const u8 {
    return a.dupeZ(u8, s);
}

fn strerror(e: c_int) []const u8 {
    return std.mem.span(sys.strerror(e));
}

fn cat(a: Allocator, parts: []const []const u8) Failure![]const u8 {
    return std.mem.concat(a, u8, parts);
}

// ---------------------------------------------------------------------------------------------------------------
// Failures: said in the person's language and in English, from the engine's own catalog

pub fn setErr(ctx: *Ctx, msg: []const u8, args: []const []const u8) Failure!void {
    var values: std.ArrayList(Value) = .empty;
    for (args) |x| try values.append(ctx.a, .{ .string = x });
    const local = try render(ctx, engine_package, msg, values.items, null);
    const en = try render(ctx, engine_package, msg, values.items, "en");
    ctx.err_local = local.text;
    ctx.err_lang = local.lang;
    ctx.err_en = en.text;
}

pub fn fail(ctx: *Ctx, msg: []const u8, args: []const []const u8) Failure {
    setErr(ctx, msg, args) catch |e| return e;
    return error.Failed;
}

// ---------------------------------------------------------------------------------------------------------------
// Files

pub fn readFile(a: Allocator, path: []const u8) ![]u8 {
    const fd = sys.open(try z(a, path), sys.O_RDONLY | sys.O_CLOEXEC);
    if (fd < 0) return errnoError();
    defer _ = sys.close(fd);
    var out: std.ArrayList(u8) = .empty;
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = sys.read(fd, &buf, buf.len);
        if (n < 0) {
            if (sys.errno() == sys.EINTR) continue;
            return errnoError();
        }
        if (n == 0) break;
        try out.appendSlice(a, buf[0..@intCast(n)]);
    }
    return out.items;
}

var last_errno: c_int = 0;

fn errnoError() error{ NotFound, System } {
    last_errno = sys.errno();
    return if (last_errno == sys.ENOENT) error.NotFound else error.System;
}

pub fn writeAll(fd: c_int, bytes: []const u8) bool {
    var rest = bytes;
    while (rest.len > 0) {
        const n = sys.write(fd, rest.ptr, rest.len);
        if (n < 0) {
            if (sys.errno() == sys.EINTR) continue;
            return false;
        }
        rest = rest[@intCast(n)..];
    }
    return true;
}

// Creates PATH (and, with PARENTS, the folders above it) with MODE; false with errno when it cannot be made
fn ensureDir(a: Allocator, path: []const u8, mode: c_uint, parents: bool) Failure!bool {
    if (sys.mkdir(try z(a, path), mode) == 0 or sys.errno() == sys.EEXIST) return true;
    if (!parents or sys.errno() != sys.ENOENT) return false;
    const cut = std.mem.lastIndexOfScalar(u8, path, '/') orelse return false;
    if (cut == 0) return false;
    if (!try ensureDir(a, path[0..cut], 0o755, true)) return false;
    return sys.mkdir(try z(a, path), mode) == 0 or sys.errno() == sys.EEXIST;
}

// Writes BYTES to DIR/NAME through DIR/.NAME.PID and a rename, synced; false with errno when it cannot
fn writeFileAtomic(a: Allocator, dir: []const u8, name: []const u8, bytes: []const u8, mode: c_uint) Failure!bool {
    const tmp = try std.fmt.allocPrint(a, "{s}/.{s}.{d}", .{ dir, name, sys.getpid() });
    const final = try cat(a, &.{ dir, "/", name });
    const tmpz = try z(a, tmp);
    const fd = sys.open(tmpz, sys.O_WRONLY | sys.O_CREAT | sys.O_TRUNC | sys.O_NOFOLLOW | sys.O_CLOEXEC, @as(c_uint, mode));
    if (fd < 0) return false;
    var ok = writeAll(fd, bytes) and sys.fchmod(fd, mode) == 0 and sys.fsync(fd) == 0;
    const saved = sys.errno();
    if (sys.close(fd) != 0) ok = false;
    if (ok and sys.rename(tmpz, try z(a, final)) == 0) return true;
    const e = if (ok) sys.errno() else saved;
    _ = sys.unlink(tmpz);
    sys.__errno_location().* = e;
    return false;
}

// ---------------------------------------------------------------------------------------------------------------
// Time, identities

pub fn nowIso(a: Allocator) Failure![]const u8 {
    var t = sys.time(null);
    var tm: sys.Tm = undefined;
    _ = sys.gmtime_r(&t, &tm);
    return std.fmt.allocPrint(a, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        @as(u32, @intCast(tm.year + 1900)), @as(u32, @intCast(tm.mon + 1)), @as(u32, @intCast(tm.mday)),
        @as(u32, @intCast(tm.hour)),        @as(u32, @intCast(tm.min)),     @as(u32, @intCast(tm.sec)),
    });
}

fn hex(a: Allocator, bytes: []const u8) Failure![]const u8 {
    const digits = "0123456789abcdef";
    const out = try a.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[2 * i] = digits[b >> 4];
        out[2 * i + 1] = digits[b & 15];
    }
    return out;
}

fn randomId(a: Allocator) Failure![]const u8 {
    var b: [16]u8 = undefined;
    if (sys.getrandom(&b, b.len, 0) != b.len) {
        // an occurrence's name, not a secret: the time and the process are enough to tell two apart
        const t: u64 = @bitCast(sys.time(null));
        const p: u64 = @intCast(sys.getpid());
        std.mem.writeInt(u64, b[0..8], t, .little);
        std.mem.writeInt(u64, b[8..16], p, .little);
    }
    return hex(a, &b);
}

// RFC 9562 version 5 (SHA-1, name-based), URL namespace 6ba7b811-9dad-11d1-80b4-00c04fd430c8
pub fn messageId(a: Allocator, package: []const u8, key: []const u8) Failure![]const u8 {
    const ns = [16]u8{ 0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8 };
    var h = std.crypto.hash.Sha1.init(.{});
    h.update(&ns);
    h.update("https://sparkylinux.org/problems/");
    h.update(package);
    h.update("/");
    h.update(key);
    var d: [20]u8 = undefined;
    h.final(&d);
    d[6] = (d[6] & 0x0f) | 0x50;
    d[8] = (d[8] & 0x3f) | 0x80;
    return hex(a, d[0..16]);
}

// Debian Policy 5.6.1: lower-case letters, digits, plus, minus and full stop, at least two, starting alphanumeric
pub fn validPackage(p: []const u8) bool {
    if (p.len < 2 or p.len > 128) return false;
    if (!std.ascii.isLower(p[0]) and !std.ascii.isDigit(p[0])) return false;
    for (p) |c| {
        if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '+' and c != '-' and c != '.') return false;
    }
    return true;
}

pub fn validKey(k: []const u8) bool {
    if (k.len == 0 or k.len > 200) return false;
    for (k) |c| if (c < 0x20 or c == 0x7f) return false;
    return true;
}

fn encodeKey(a: Allocator, key: []const u8) Failure![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (key, 0..) |c, i| {
        const plain = std.ascii.isAlphanumeric(c) or c == '_' or c == '@' or c == ':' or c == '+' or c == '-' or (c == '.' and i > 0);
        if (plain) {
            try out.append(a, c);
        } else {
            try out.print(a, "%{X:0>2}", .{c});
        }
    }
    return out.items;
}

// ---------------------------------------------------------------------------------------------------------------
// Languages

fn isCLocale(v: []const u8) bool {
    return std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX") or std.mem.startsWith(u8, v, "C.");
}

fn defaultLocale(ctx: *Ctx) Failure!?[]const u8 {
    const text = readFile(ctx.a, try cat(ctx.a, &.{ ctx.root, "/etc/default/locale" })) catch return null;
    var found: [3]?[]const u8 = .{ null, null, null };
    const names = [_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" };
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t\"'");
        for (names, 0..) |n, i| {
            if (std.mem.eql(u8, line[0..eq], n) and value.len > 0) found[i] = value;
        }
    }
    for (found) |f| if (f) |v| return v;
    return null;
}

fn addLanguage(a: Allocator, list: *std.ArrayList([]const u8), raw: []const u8) Failure!void {
    var base = raw;
    if (std.mem.indexOfAny(u8, base, ".@")) |cut| base = base[0..cut];
    if (base.len == 0 or isCLocale(base)) return;
    var codes: [3][]const u8 = undefined;
    var n: usize = 0;
    codes[n] = base;
    n += 1;
    if (std.mem.startsWith(u8, base, "zh")) {
        // Chinese keeps its script: Hong Kong and Macau write Traditional Chinese, the rest Simplified
        const traditional = std.mem.eql(u8, base, "zh_TW") or std.mem.eql(u8, base, "zh_HK") or std.mem.eql(u8, base, "zh_MO");
        codes[n] = if (traditional) "zh_TW" else "zh_CN";
        n += 1;
    } else if (std.mem.indexOfScalar(u8, base, '_')) |u| {
        codes[n] = base[0..u];
        n += 1;
    }
    for (codes[0..n]) |code| {
        for (list.items) |have| {
            if (std.mem.eql(u8, have, code)) break;
        } else try list.append(a, code);
    }
}

// The person's languages, most wanted first; English, which every catalog has, is not listed
pub fn languages(ctx: *Ctx) Failure![]const []const u8 {
    if (ctx.langs) |l| return l;
    var list: std.ArrayList([]const u8) = .empty;
    var value: ?[]const u8 = env("LC_ALL") orelse env("LC_MESSAGES") orelse env("LANG");
    if (value == null) value = try defaultLocale(ctx);
    if (value) |v| {
        if (!isCLocale(v)) {
            if (env("LANGUAGE")) |language| {
                var parts = std.mem.splitScalar(u8, language, ':');
                while (parts.next()) |p| try addLanguage(ctx.a, &list, p);
            }
            try addLanguage(ctx.a, &list, v);
        }
    }
    ctx.langs = list.items;
    return list.items;
}

fn languagesFor(ctx: *Ctx, wanted: ?[]const u8) Failure![]const []const u8 {
    const w = wanted orelse return languages(ctx);
    var list: std.ArrayList([]const u8) = .empty;
    if (!std.mem.eql(u8, w, "en")) {
        var parts = std.mem.splitScalar(u8, w, ':');
        while (parts.next()) |p| try addLanguage(ctx.a, &list, p);
    }
    return list.items;
}

// ---------------------------------------------------------------------------------------------------------------
// Catalogs (systemd's journal message catalog format: "-- ID", header lines, an empty line, the text)

fn parseCatalog(a: Allocator, text: []const u8) Failure!Catalog {
    var catalog: Catalog = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var id: ?[]const u8 = null;
    var subject: []const u8 = "";
    var in_body = false;
    var body: std.ArrayList(u8) = .empty;
    while (true) {
        const next = lines.next();
        const starts = if (next) |l| l.len >= 35 and std.mem.startsWith(u8, l, "-- ") and (l.len == 35 or l[35] == ' ') else true;
        if (starts) {
            if (id) |i| {
                const trimmed = std.mem.trimEnd(u8, body.items, "\n");
                try catalog.put(a, i, .{ .subject = subject, .body = try a.dupe(u8, trimmed) });
            }
            const l = next orelse break;
            id = try std.ascii.allocLowerString(a, l[3..35]);
            subject = "";
            in_body = false;
            body = .empty;
            continue;
        }
        const line = next.?;
        if (id == null) continue;
        if (!in_body) {
            if (line.len == 0) {
                in_body = true;
            } else if (std.mem.startsWith(u8, line, "Subject:")) {
                subject = std.mem.trim(u8, line["Subject:".len..], " \t");
            }
            continue;
        }
        try body.appendSlice(a, line);
        try body.append(a, '\n');
    }
    return catalog;
}

fn loadCatalog(ctx: *Ctx, package: []const u8, lang: []const u8) Failure!?*const Catalog {
    const name = if (std.mem.eql(u8, lang, "en"))
        try cat(ctx.a, &.{ package, ".catalog" })
    else
        try cat(ctx.a, &.{ package, ".", lang, ".catalog" });
    const slot = try ctx.catalogs.getOrPut(ctx.a, name);
    if (!slot.found_existing) {
        slot.value_ptr.* = null;
        var dirs = std.mem.splitScalar(u8, ctx.catalog_dir, ':');
        while (dirs.next()) |dir| {
            if (dir.len == 0) continue;
            if (readFile(ctx.a, try cat(ctx.a, &.{ dir, "/", name }))) |text| {
                slot.value_ptr.* = try parseCatalog(ctx.a, text);
                break;
            } else |_| {}
        }
    }
    if (slot.value_ptr.*) |*c| return c;
    return null;
}

fn lookup(ctx: *Ctx, package: []const u8, msg: []const u8, langs: []const []const u8) Failure!?struct { entry: Entry, lang: []const u8 } {
    const id = try messageId(ctx.a, package, msg);
    for (langs) |l| {
        if (try loadCatalog(ctx, package, l)) |c| {
            if (c.get(id)) |e| return .{ .entry = e, .lang = l };
        }
    }
    if (try loadCatalog(ctx, package, "en")) |c| {
        if (c.get(id)) |e| return .{ .entry = e, .lang = "en" };
    }
    return null;
}

pub fn hasMessage(ctx: *Ctx, package: []const u8, msg: []const u8) Failure!bool {
    return (try lookup(ctx, package, msg, &.{})) != null;
}

fn renderArg(ctx: *Ctx, package: []const u8, arg: Value, lang: []const u8, depth: u8) Failure![]const u8 {
    switch (arg) {
        .string => |s| {
            if (depth < 4 and s.len > 1 and s[0] == '@' and try hasMessage(ctx, package, s[1..])) {
                return (try renderIn(ctx, package, s[1..], &.{}, lang, depth + 1)).text;
            }
            return s;
        },
        .array => |arr| {
            if (depth < 4 and arr.items.len > 0 and arr.items[0] == .string) {
                return (try renderIn(ctx, package, arr.items[0].string, arr.items[1..], lang, depth + 1)).text;
            }
            return "";
        },
        .integer => |i| return std.fmt.allocPrint(ctx.a, "{d}", .{i}),
        .bool => |b| return if (b) "true" else "false",
        else => return "",
    }
}

fn substitute(ctx: *Ctx, package: []const u8, template: []const u8, args: []const Value, lang: []const u8, depth: u8) Failure![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    const mark = "@SPARKY_ARG_";
    while (i < template.len) {
        // @SPARKY_ARG_A@ is the first argument: systemd's catalogs name a field with capital letters and underscores only
        // (replace-var.c), so the arguments are lettered, A to Z
        if (std.mem.startsWith(u8, template[i..], mark) and i + mark.len + 1 < template.len and template[i + mark.len + 1] == '@') {
            const letter = template[i + mark.len];
            if (letter >= 'A' and letter <= 'Z' and letter - 'A' < args.len) {
                try out.appendSlice(ctx.a, try renderArg(ctx, package, args[letter - 'A'], lang, depth));
                i += mark.len + 2;
                continue;
            }
        }
        try out.append(ctx.a, template[i]);
        i += 1;
    }
    return out.items;
}

fn renderIn(ctx: *Ctx, package: []const u8, msg: []const u8, args: []const Value, lang: []const u8, depth: u8) Failure!Rendered {
    const langs = try languagesFor(ctx, lang);
    if (try lookup(ctx, package, msg, langs)) |found| {
        return .{
            .title = try substitute(ctx, package, found.entry.subject, args, found.lang, depth),
            .text = try substitute(ctx, package, found.entry.body, args, found.lang, depth),
            .lang = found.lang,
        };
    }
    // a message no catalog has is still said, with its name and arguments, never left out
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(ctx.a, msg);
    for (args) |x| {
        try out.append(ctx.a, ' ');
        try out.appendSlice(ctx.a, try renderArg(ctx, package, x, "en", depth));
    }
    return .{ .title = package, .text = out.items, .lang = "en", .found = false };
}

// MSG of PACKAGE with ARGS in LANG (a language list as LANGUAGE writes it), or in the person's languages when null
pub fn render(ctx: *Ctx, package: []const u8, msg: []const u8, args: []const Value, lang: ?[]const u8) Failure!Rendered {
    const langs = try languagesFor(ctx, lang);
    if (try lookup(ctx, package, msg, langs)) |found| {
        return renderIn(ctx, package, msg, args, found.lang, 0);
    }
    return renderIn(ctx, package, msg, args, "en", 0);
}

// A kept problem as the person reads it: its message, then its further sentences, in LANG or the person's languages.
// When no catalog has its message any more (a removed package, a renamed key) it is its English text as kept, under
// the engine's own title, never the bare key and arguments
pub fn renderRecord(ctx: *Ctx, r: Record, lang: ?[]const u8) Failure!Rendered {
    const main = try render(ctx, r.package, r.message, r.args, lang);
    if (!main.found and r.text_en.len > 0) {
        const title = try render(ctx, engine_package, "LOCAL29", &.{}, lang);
        return .{ .title = title.text, .text = r.text_en, .lang = "en", .found = false };
    }
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(ctx.a, main.text);
    for (r.more) |m| {
        const sentence = try renderArg(ctx, r.package, m, main.lang, 0);
        if (sentence.len == 0) continue;
        try out.append(ctx.a, ' ');
        try out.appendSlice(ctx.a, sentence);
    }
    return .{ .title = main.title, .text = out.items, .lang = main.lang, .found = main.found };
}

// ---------------------------------------------------------------------------------------------------------------
// JSON

const Writer = struct {
    a: Allocator,
    out: std.ArrayList(u8) = .empty,
    comma: [24]bool = undefined,
    depth: usize = 0,
    after_key: bool = false,

    fn raw(w: *Writer, s: []const u8) Failure!void {
        try w.out.appendSlice(w.a, s);
    }
    fn sep(w: *Writer) Failure!void {
        if (w.after_key) {
            w.after_key = false;
            return;
        }
        if (w.depth > 0) {
            if (w.comma[w.depth - 1]) try w.raw(",");
            w.comma[w.depth - 1] = true;
        }
    }
    fn open(w: *Writer, c: []const u8) Failure!void {
        try w.sep();
        try w.raw(c);
        w.comma[w.depth] = false;
        w.depth += 1;
    }
    fn close(w: *Writer, c: []const u8) Failure!void {
        w.depth -= 1;
        try w.raw(c);
    }
    fn key(w: *Writer, k: []const u8) Failure!void {
        try w.str(k);
        try w.raw(":");
        w.after_key = true;
    }
    fn str(w: *Writer, s: []const u8) Failure!void {
        try w.sep();
        try w.raw("\"");
        var i: usize = 0;
        while (i < s.len) {
            const c = s[i];
            if (c >= 0x80) {
                // invalid UTF-8 (a command's output can hold any bytes) is written as U+FFFD
                const n = std.unicode.utf8ByteSequenceLength(c) catch 0;
                if (n > 0 and i + n <= s.len) {
                    if (std.unicode.utf8Decode(s[i .. i + n])) |_| {
                        try w.raw(s[i .. i + n]);
                        i += n;
                        continue;
                    } else |_| {}
                }
                try w.raw("\\ufffd");
                i += 1;
                continue;
            }
            switch (c) {
                '"' => try w.raw("\\\""),
                '\\' => try w.raw("\\\\"),
                '\n' => try w.raw("\\n"),
                '\r' => try w.raw("\\r"),
                '\t' => try w.raw("\\t"),
                0...8, 11, 12, 14...0x1f, 0x7f => try w.out.print(w.a, "\\u{x:0>4}", .{c}),
                else => try w.out.append(w.a, c),
            }
            i += 1;
        }
        try w.raw("\"");
    }
    fn int(w: *Writer, n: i64) Failure!void {
        try w.sep();
        try w.out.print(w.a, "{d}", .{n});
    }
    fn boolean(w: *Writer, b: bool) Failure!void {
        try w.sep();
        try w.raw(if (b) "true" else "false");
    }
    fn nul(w: *Writer) Failure!void {
        try w.sep();
        try w.raw("null");
    }
    fn strings(w: *Writer, list: []const []const u8) Failure!void {
        try w.open("[");
        for (list) |s| try w.str(s);
        try w.close("]");
    }
    fn value(w: *Writer, v: Value) Failure!void {
        switch (v) {
            .null => try w.nul(),
            .bool => |b| try w.boolean(b),
            .integer => |i| try w.int(i),
            .float => |f| {
                try w.sep();
                try w.out.print(w.a, "{d}", .{f});
            },
            .number_string, .string => |s| try w.str(s),
            .array => |arr| {
                try w.open("[");
                for (arr.items) |x| try w.value(x);
                try w.close("]");
            },
            .object => |obj| {
                try w.open("{");
                var it = obj.iterator();
                while (it.next()) |e| {
                    try w.key(e.key_ptr.*);
                    try w.value(e.value_ptr.*);
                }
                try w.close("}");
            },
        }
    }
};

fn writeRecordFields(w: *Writer, ctx: *Ctx, r: Record) Failure!void {
    try w.key("package");
    try w.str(r.package);
    try w.key("key");
    try w.str(r.key);
    try w.key("message");
    try w.str(r.message);
    try w.key("message_id");
    try w.str(try messageId(ctx.a, r.package, r.message));
    try w.key("args");
    try w.open("[");
    for (r.args) |x| try w.value(x);
    try w.close("]");
    try w.key("severity");
    try w.str(@tagName(r.severity));
    try w.key("id");
    try w.str(r.id);
    try w.key("generation");
    try w.int(r.generation);
    try w.key("first");
    try w.str(r.first);
    try w.key("time");
    try w.str(r.time);
    try w.key("changed");
    try w.str(r.changed);
    try w.key("command");
    if (r.command) |c| try w.strings(c) else try w.nul();
    try w.key("status");
    if (r.status) |s| try w.int(s) else try w.nul();
    try w.key("output");
    try w.str(r.output);
    try w.key("repair");
    try w.open("[");
    for (r.repair) |c| try w.strings(c);
    try w.close("]");
    try w.key("actions");
    try w.open("[");
    for (r.actions) |act| {
        try w.open("{");
        try w.key("id");
        try w.str(act.id);
        try w.key("label");
        try w.open("[");
        for (act.label) |x| try w.value(x);
        try w.close("]");
        try w.key("command");
        try w.strings(act.command);
        try w.close("}");
    }
    try w.close("]");
    try w.key("unit");
    if (r.unit) |u| try w.str(u) else try w.nul();
    try w.key("repairs_failed");
    try w.int(r.repairs_failed);
    try w.key("more");
    try w.open("[");
    for (r.more) |x| try w.value(x);
    try w.close("]");
    try w.key("text_en");
    try w.str(r.text_en);
    try w.key("data");
    if (r.data) |d| try w.value(d) else try w.nul();
    try w.key("kept_ns");
    try w.int(r.kept_ns);
    try w.key("last_repair");
    if (r.last_repair) |lr| {
        try w.open("{");
        try w.key("time");
        try w.str(lr.time);
        try w.key("command");
        try w.strings(lr.command);
        try w.key("status");
        try w.int(lr.status);
        try w.key("output");
        try w.str(lr.output);
        try w.close("}");
    } else try w.nul();
}

fn recordJson(ctx: *Ctx, r: Record) Failure![]const u8 {
    var w = Writer{ .a = ctx.a };
    try w.open("{");
    try writeRecordFields(&w, ctx, r);
    try w.close("}");
    try w.raw("\n");
    return w.out.items;
}

fn field(obj: std.json.ObjectMap, name: []const u8) ?Value {
    const v = obj.get(name) orelse return null;
    return if (v == .null) null else v;
}

fn fieldStr(obj: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const v = field(obj, name) orelse return null;
    return if (v == .string) v.string else null;
}

fn fieldInt(obj: std.json.ObjectMap, name: []const u8) ?i64 {
    const v = field(obj, name) orelse return null;
    return if (v == .integer) v.integer else null;
}

pub const BadValue = error{BadValue} || Failure;

pub fn stringList(a: Allocator, v: Value) BadValue![]const []const u8 {
    if (v != .array) return error.BadValue;
    var out: std.ArrayList([]const u8) = .empty;
    for (v.array.items) |x| {
        if (x != .string) return error.BadValue;
        try out.append(a, x.string);
    }
    return out.items;
}

fn argList(v: Value) BadValue![]const Value {
    if (v != .array) return error.BadValue;
    for (v.array.items) |x| {
        if (x != .string and x != .array and x != .integer) return error.BadValue;
    }
    return v.array.items;
}

// Fills the optional parts of R from a JSON object (a record's file, or a caller's details); error.BadValue names
// nothing in particular: the caller says which input it was
pub fn applyDetails(a: Allocator, r: *Record, obj: std.json.ObjectMap) BadValue!void {
    if (field(obj, "args")) |v| r.args = try argList(v);
    if (fieldStr(obj, "severity")) |s| r.severity = Severity.parse(s) orelse return error.BadValue;
    if (field(obj, "command")) |v| r.command = try stringList(a, v);
    if (field(obj, "status")) |v| r.status = if (v == .integer) v.integer else return error.BadValue;
    if (fieldStr(obj, "output")) |s| r.output = s;
    if (field(obj, "repair")) |v| {
        if (v != .array) return error.BadValue;
        var list: std.ArrayList([]const []const u8) = .empty;
        for (v.array.items) |c| {
            const cmd = try stringList(a, c);
            if (cmd.len == 0) return error.BadValue;
            try list.append(a, cmd);
        }
        r.repair = list.items;
    }
    if (field(obj, "actions")) |v| {
        if (v != .array) return error.BadValue;
        var list: std.ArrayList(Action) = .empty;
        for (v.array.items) |x| try list.append(a, try parseAction(a, x));
        r.actions = list.items;
    }
    if (fieldStr(obj, "unit")) |s| r.unit = s;
    if (field(obj, "more")) |v| r.more = try argList(v);
    if (fieldStr(obj, "first")) |f| r.first = f;
    if (field(obj, "data")) |v| {
        if (v != .object) return error.BadValue;
        r.data = v;
    }
}

pub fn parseAction(a: Allocator, x: Value) BadValue!Action {
    if (x != .object) return error.BadValue;
    const id = fieldStr(x.object, "id") orelse return error.BadValue;
    const label = try argList(field(x.object, "label") orelse return error.BadValue);
    if (label.len == 0 or label[0] != .string) return error.BadValue;
    const command = try stringList(a, field(x.object, "command") orelse return error.BadValue);
    if (command.len == 0) return error.BadValue;
    return .{ .id = id, .label = label, .command = command };
}

fn parseRecord(a: Allocator, text: []const u8) BadValue!Record {
    const v = std.json.parseFromSliceLeaky(Value, a, text, .{}) catch return error.BadValue;
    if (v != .object) return error.BadValue;
    const o = v.object;
    var r = Record{
        .package = fieldStr(o, "package") orelse return error.BadValue,
        .key = fieldStr(o, "key") orelse return error.BadValue,
        .message = fieldStr(o, "message") orelse return error.BadValue,
        .id = fieldStr(o, "id") orelse "",
        .generation = fieldInt(o, "generation") orelse 1,
        .first = fieldStr(o, "first") orelse "",
        .time = fieldStr(o, "time") orelse "",
        .changed = fieldStr(o, "changed") orelse "",
        .repairs_failed = fieldInt(o, "repairs_failed") orelse 0,
        .text_en = fieldStr(o, "text_en") orelse "",
        .kept_ns = fieldInt(o, "kept_ns") orelse 0,
    };
    try applyDetails(a, &r, o);
    if (field(o, "last_repair")) |lr| {
        if (lr == .object) {
            r.last_repair = .{
                .time = fieldStr(lr.object, "time") orelse "",
                .command = if (field(lr.object, "command")) |c| try stringList(a, c) else &.{},
                .status = fieldInt(lr.object, "status") orelse 0,
                .output = fieldStr(lr.object, "output") orelse "",
            };
        }
    }
    return r;
}

fn argsJson(ctx: *Ctx, args: []const Value) Failure![]const u8 {
    var w = Writer{ .a = ctx.a };
    try w.open("[");
    for (args) |x| try w.value(x);
    try w.close("]");
    return w.out.items;
}

// ---------------------------------------------------------------------------------------------------------------
// The stores

pub fn personDir(ctx: *Ctx) Failure!?[]const u8 {
    if (ctx.under_pkexec) return null;
    if (env("XDG_STATE_HOME")) |s| {
        if (s[0] == '/') return try cat(ctx.a, &.{ s, "/sparky-stereo-problems" });
    }
    if (env("HOME")) |h| return try cat(ctx.a, &.{ h, "/.local/state/sparky-stereo-problems" });
    if (sys.getpwuid(sys.getuid())) |pw| return try cat(ctx.a, &.{ std.mem.span(pw.dir), "/.local/state/sparky-stereo-problems" });
    return null;
}

pub fn storeDir(ctx: *Ctx, scope: Scope) Failure!?[]const u8 {
    return switch (scope) {
        .machine => try cat(ctx.a, &.{ ctx.root, "/var/lib/sparky-stereo-problems" }),
        .boot => try cat(ctx.a, &.{ ctx.root, "/run/sparky-stereo-problems" }),
        .person => try personDir(ctx),
    };
}

pub fn defaultScope(ctx: *Ctx) Scope {
    return if (ctx.euid == 0) .machine else .person;
}

fn recordName(ctx: *Ctx, package: []const u8, key: []const u8) Failure![]const u8 {
    return cat(ctx.a, &.{ package, "_", try encodeKey(ctx.a, key), ".json" });
}

fn checkNames(ctx: *Ctx, package: []const u8, key: []const u8) Failure!void {
    if (!validPackage(package)) return fail(ctx, "LOCAL30", &.{package});
    if (!validKey(key)) return fail(ctx, "LOCAL31", &.{ key, package });
}

fn needDir(ctx: *Ctx, scope: Scope, package: []const u8, key: []const u8) Failure![]const u8 {
    return (try storeDir(ctx, scope)) orelse return fail(ctx, "LOCAL15", &.{ key, package, @tagName(scope), "no home folder" });
}

const Lock = struct {
    fd: c_int,
    fn release(l: Lock) void {
        _ = sys.flock(l.fd, sys.LOCK_UN);
        _ = sys.close(l.fd);
    }
};

fn lockStore(ctx: *Ctx, scope: Scope, dir: []const u8) Failure!?Lock {
    const mode: c_uint = if (scope == .person) 0o700 else 0o755;
    // the folders above are made too: a person's ~/.local/state, or a test's SPARKY_STEREO_ROOT
    if (!try ensureDir(ctx.a, dir, mode, true)) return null;
    const fd = sys.open(try z(ctx.a, try cat(ctx.a, &.{ dir, "/.lock" })), sys.O_RDWR | sys.O_CREAT | sys.O_CLOEXEC | sys.O_NOFOLLOW, @as(c_uint, 0o644));
    if (fd < 0) return null;
    while (sys.flock(fd, sys.LOCK_EX) != 0) {
        if (sys.errno() != sys.EINTR) {
            const e = sys.errno();
            _ = sys.close(fd);
            sys.__errno_location().* = e;
            return null;
        }
    }
    return Lock{ .fd = fd };
}

pub const ReadResult = union(enum) {
    missing,
    record: Record,
    unreadable: []const u8,
};

pub fn readRecord(ctx: *Ctx, path: []const u8) Failure!ReadResult {
    const text = readFile(ctx.a, path) catch |e| switch (e) {
        error.NotFound => return .missing,
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .unreadable = strerror(last_errno) },
    };
    const r = parseRecord(ctx.a, text) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .unreadable = "not a problem record (JSON with package, key and message)" },
    };
    return .{ .record = r };
}

// ---------------------------------------------------------------------------------------------------------------
// The journal

const JField = struct { name: []const u8, value: []const u8 };

// The journal field of the argument at INDEX: SPARKY_ARG_A for the first (the name its catalog entry uses)
fn argField(a: Allocator, index: usize) Failure![]const u8 {
    return std.fmt.allocPrint(a, "SPARKY_ARG_{c}", .{@as(u8, @intCast('A' + index))});
}

fn journalSend(ctx: *Ctx, fields: []const JField) Failure!void {
    var iov: std.ArrayList(sys.iovec) = .empty;
    for (fields) |f| {
        const line = try cat(ctx.a, &.{ f.name, "=", f.value });
        try iov.append(ctx.a, .{ .base = line.ptr, .len = line.len });
    }
    // libsystemd drops a message without a word when no journal listens (journal-send.c: "Fail silently if the
    // journal is not available"), as in a chroot: that is said too
    if (sys.access("/run/systemd/journal/socket", 0) != 0) {
        ctx.journal_error = strerror(sys.errno());
        return;
    }
    const r = sys.sd_journal_sendv(iov.items.ptr, @intCast(iov.items.len));
    if (r < 0) ctx.journal_error = strerror(-r);
}

fn problemFields(ctx: *Ctx, list: *std.ArrayList(JField), scope: Scope, r: Record, file: []const u8) Failure!void {
    try list.append(ctx.a, .{ .name = "SYSLOG_IDENTIFIER", .value = r.package });
    try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_PACKAGE", .value = r.package });
    try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_KEY", .value = r.key });
    try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_SCOPE", .value = @tagName(scope) });
    try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_SEVERITY", .value = @tagName(r.severity) });
    try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_MESSAGE_ID", .value = try messageId(ctx.a, r.package, r.message) });
    if (file.len > 0) try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_RECORD", .value = file });
    if (r.command) |c| try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_COMMAND", .value = try std.mem.join(ctx.a, " ", c) });
    if (r.status) |s| try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_STATUS", .value = try std.fmt.allocPrint(ctx.a, "{d}", .{s}) });
    if (r.unit) |u| try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_UNIT", .value = u });
}

// The problem itself, with its own MESSAGE_ID and its arguments as the fields its catalog entry names
fn journalProblem(ctx: *Ctx, event: []const u8, scope: Scope, r: Record, file: []const u8) Failure!void {
    var list: std.ArrayList(JField) = .empty;
    const en = try renderRecord(ctx, r, "en");
    try list.append(ctx.a, .{ .name = "MESSAGE", .value = en.text });
    try list.append(ctx.a, .{ .name = "MESSAGE_ID", .value = try messageId(ctx.a, r.package, r.message) });
    try list.append(ctx.a, .{ .name = "PRIORITY", .value = r.severity.priority() });
    try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_EVENT", .value = event });
    for (r.args, 0..) |x, i| {
        if (i >= 26) break;
        try list.append(ctx.a, .{ .name = try argField(ctx.a, i), .value = try renderArg(ctx, r.package, x, "en", 0) });
    }
    try problemFields(ctx, &list, scope, r, file);
    if (r.output.len > 0) try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_OUTPUT", .value = r.output });
    try journalSend(ctx, list.items);
}

// An event of the engine about a problem (repaired, hidden...): the engine's message MSG with ARGS
fn journalEvent(ctx: *Ctx, event: []const u8, msg: []const u8, args: []const []const u8, priority: []const u8, scope: Scope, r: Record, file: []const u8) Failure!void {
    var values: std.ArrayList(Value) = .empty;
    for (args) |x| try values.append(ctx.a, .{ .string = x });
    var list: std.ArrayList(JField) = .empty;
    const en = try render(ctx, engine_package, msg, values.items, "en");
    try list.append(ctx.a, .{ .name = "MESSAGE", .value = en.text });
    try list.append(ctx.a, .{ .name = "MESSAGE_ID", .value = try messageId(ctx.a, engine_package, msg) });
    try list.append(ctx.a, .{ .name = "PRIORITY", .value = priority });
    try list.append(ctx.a, .{ .name = "SPARKY_PROBLEM_EVENT", .value = event });
    for (args, 0..) |x, i| {
        if (i >= 26) break;
        try list.append(ctx.a, .{ .name = try argField(ctx.a, i), .value = x });
    }
    try problemFields(ctx, &list, scope, r, file);
    try journalSend(ctx, list.items);
}

// ---------------------------------------------------------------------------------------------------------------
// keep, clear

fn sameMessage(ctx: *Ctx, old: Record, new: Record) Failure!bool {
    return std.mem.eql(u8, old.message, new.message) and std.mem.eql(u8, try argsJson(ctx, old.args), try argsJson(ctx, new.args));
}

// Keeps R in SCOPE: a problem kept again keeps its id, its first time and its hide while its message is the same;
// a new message makes it a new generation, which shows again where it was hidden. Every keep is in the journal, also
// one whose record cannot be written (then error.Failed, said)
pub fn keep(ctx: *Ctx, scope: Scope, input: Record) Failure!Record {
    try checkNames(ctx, input.package, input.key);
    if (input.message.len == 0) return fail(ctx, "LOCAL31", &.{ input.message, input.package });
    const dir = try needDir(ctx, scope, input.package, input.key);
    const name = try recordName(ctx, input.package, input.key);
    const path = try cat(ctx.a, &.{ dir, "/", name });
    const now = try nowIso(ctx.a);
    var r = input;
    r.time = now;
    var ts: sys.Timespec = undefined;
    _ = sys.clock_gettime(0, &ts);
    r.kept_ns = ts.sec * 1_000_000_000 + ts.nsec;
    r.text_en = "";
    r.text_en = (try renderRecord(ctx, r, "en")).text;
    const lock = (try lockStore(ctx, scope, dir)) orelse {
        const e = strerror(sys.errno());
        r.first = now;
        try journalProblem(ctx, "not-kept", scope, r, "");
        return fail(ctx, "LOCAL15", &.{ input.key, input.package, dir, e });
    };
    defer lock.release();
    switch (try readRecord(ctx, path)) {
        .record => |old| {
            r.id = if (old.id.len > 0) old.id else try randomId(ctx.a);
            r.first = if (old.first.len > 0) old.first else now;
            const same = try sameMessage(ctx, old, input);
            r.generation = if (same) old.generation else old.generation + 1;
            r.changed = if (same and old.changed.len > 0) old.changed else now;
            r.repairs_failed = old.repairs_failed;
            r.last_repair = old.last_repair;
        },
        else => {
            r.id = try randomId(ctx.a);
            // a problem moved from an older store keeps the time it was first found (Steps.migrate)
            r.first = if (input.first.len > 0) input.first else now;
            r.generation = 1;
            r.changed = now;
        },
    }
    const mode: c_uint = if (scope == .person) 0o600 else 0o644;
    if (!try writeFileAtomic(ctx.a, dir, name, try recordJson(ctx, r), mode)) {
        const e = strerror(sys.errno());
        try journalProblem(ctx, "not-kept", scope, r, "");
        return fail(ctx, "LOCAL15", &.{ input.key, input.package, dir, e });
    }
    try journalProblem(ctx, "kept", scope, r, path);
    return r;
}

// The step works again: its record goes. True when there was one
pub fn clear(ctx: *Ctx, scope: Scope, package: []const u8, key: []const u8) Failure!bool {
    try checkNames(ctx, package, key);
    const dir = (try storeDir(ctx, scope)) orelse return false;
    const path = try cat(ctx.a, &.{ dir, "/", try recordName(ctx, package, key) });
    const old = try readRecord(ctx, path);
    if (old == .missing) return false;
    const lock = (try lockStore(ctx, scope, dir)) orelse return fail(ctx, "LOCAL28", &.{ key, package, dir, strerror(sys.errno()) });
    defer lock.release();
    if (sys.unlink(try z(ctx.a, path)) != 0) {
        if (sys.errno() == sys.ENOENT) return false;
        return fail(ctx, "LOCAL28", &.{ key, package, dir, strerror(sys.errno()) });
    }
    const r = if (old == .record) old.record else Record{ .package = package, .key = key, .message = "" };
    try journalEvent(ctx, "cleared", "LOCAL13", &.{ key, package }, "6", scope, r, path);
    return true;
}

// Says MSG of PACKAGE: kept nowhere, in the journal as a notice; returns it in the person's language and in English
pub fn say(ctx: *Ctx, package: []const u8, msg: []const u8, args: []const Value) Failure![2]Rendered {
    if (!validPackage(package)) return fail(ctx, "LOCAL30", &.{package});
    const r = Record{ .package = package, .key = msg, .message = msg, .args = args, .severity = .notice };
    try journalProblem(ctx, "said", defaultScope(ctx), r, "");
    return .{ try render(ctx, package, msg, args, null), try render(ctx, package, msg, args, "en") };
}

// ---------------------------------------------------------------------------------------------------------------
// Commands

pub const Ran = struct {
    status: i64,
    output: []const u8,
};

// Runs ARGV with its output shown on standard error as it comes; its exit status (128 + N for signal N, 127 when it
// cannot be started) and the end of its output
pub fn execute(ctx: *Ctx, argv: []const []const u8) Failure!Ran {
    if (argv.len == 0) return .{ .status = 127, .output = "" };
    const c_argv = try ctx.a.allocSentinel(?[*:0]const u8, argv.len, null);
    for (argv, 0..) |x, i| c_argv[i] = try z(ctx.a, x);
    const argvp: [*:null]const ?[*:0]const u8 = c_argv.ptr;
    var fds: [2]c_int = undefined;
    if (sys.pipe(&fds) != 0) return .{ .status = 127, .output = try cat(ctx.a, &.{ argv[0], ": ", strerror(sys.errno()), "\n" }) };
    const pid = sys.fork();
    if (pid < 0) {
        _ = sys.close(fds[0]);
        _ = sys.close(fds[1]);
        return .{ .status = 127, .output = try cat(ctx.a, &.{ argv[0], ": ", strerror(sys.errno()), "\n" }) };
    }
    if (pid == 0) {
        _ = sys.dup2(fds[1], 1);
        _ = sys.dup2(fds[1], 2);
        _ = sys.close(fds[0]);
        _ = sys.close(fds[1]);
        _ = sys.execvp(c_argv[0].?, argvp);
        const e = sys.strerror(sys.errno());
        _ = writeAll(2, argv[0]);
        _ = writeAll(2, ": ");
        _ = writeAll(2, std.mem.span(e));
        _ = writeAll(2, "\n");
        sys._exit(127);
    }
    _ = sys.close(fds[1]);
    var tail: std.ArrayList(u8) = .empty;
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = sys.read(fds[0], &buf, buf.len);
        if (n < 0) {
            if (sys.errno() == sys.EINTR) continue;
            break;
        }
        if (n == 0) break;
        const chunk = buf[0..@intCast(n)];
        _ = writeAll(2, chunk);
        try tail.appendSlice(ctx.a, chunk);
        if (tail.items.len > 4 * output_bytes) {
            const drop = tail.items.len - output_bytes;
            std.mem.copyForwards(u8, tail.items[0..output_bytes], tail.items[drop..]);
            tail.shrinkRetainingCapacity(output_bytes);
        }
    }
    _ = sys.close(fds[0]);
    var st: c_int = 0;
    while (sys.waitpid(pid, &st, 0) < 0) {
        if (sys.errno() != sys.EINTR) break;
    }
    const raw: u32 = @bitCast(st);
    const status: i64 = if (raw & 0x7f == 0) @intCast((raw >> 8) & 0xff) else 128 + @as(i64, @intCast(raw & 0x7f));
    return .{ .status = status, .output = trimTail(tail.items) };
}

fn trimTail(text: []const u8) []const u8 {
    var t = text;
    if (t.len > output_bytes) {
        t = t[t.len - output_bytes ..];
        if (std.mem.indexOfScalar(u8, t, '\n')) |nl| t = t[nl + 1 ..];
    }
    var lines: usize = 0;
    var i = t.len;
    while (i > 0) : (i -= 1) {
        if (t[i - 1] == '\n' and i != t.len) {
            lines += 1;
            if (lines == output_lines) return t[i..];
        }
    }
    return t;
}

// Runs COMMAND: a success clears the record, a failure keeps it with the command, its exit status and the end of its
// output (MSG's first two arguments are the command and its status, then ARGS); its repair is the command itself
// unless the details name one. Returns the command's exit status
pub fn run(ctx: *Ctx, scope: Scope, input: Record, command: []const []const u8) Failure!i64 {
    try checkNames(ctx, input.package, input.key);
    const ran = try execute(ctx, command);
    if (ran.status == 0) {
        _ = try clear(ctx, scope, input.package, input.key);
        return 0;
    }
    var r = input;
    var args: std.ArrayList(Value) = .empty;
    try args.append(ctx.a, .{ .string = try std.mem.join(ctx.a, " ", command) });
    try args.append(ctx.a, .{ .string = try std.fmt.allocPrint(ctx.a, "{d}", .{ran.status}) });
    try args.appendSlice(ctx.a, input.args);
    r.args = args.items;
    r.command = command;
    r.status = ran.status;
    r.output = ran.output;
    if (r.repair.len == 0) {
        const list = try ctx.a.alloc([]const []const u8, 1);
        list[0] = command;
        r.repair = list;
    }
    _ = try keep(ctx, scope, r);
    return ran.status;
}

// Runs the record's repair commands in order: when all succeed the record goes (true); when one fails the record
// keeps that repair as evidence and becomes a new generation, so it shows again where it was hidden
pub fn repair(ctx: *Ctx, scope: Scope, package: []const u8, key: []const u8) Failure!i64 {
    try checkNames(ctx, package, key);
    const dir = try needDir(ctx, scope, package, key);
    const name = try recordName(ctx, package, key);
    const path = try cat(ctx.a, &.{ dir, "/", name });
    const r = switch (try readRecord(ctx, path)) {
        .missing => return fail(ctx, "LOCAL18", &.{ key, package }),
        .unreadable => |e| return fail(ctx, "LOCAL25", &.{try cat(ctx.a, &.{ path, ": ", e })}),
        .record => |x| x,
    };
    if (scope != .person and ctx.euid != 0) {
        const how = try cat(ctx.a, &.{ "pkexec sparky-stereo-problems repair --", @tagName(scope), " ", package, " ", key });
        return fail(ctx, "LOCAL17", &.{ key, package, how });
    }
    if (r.repair.len == 0) return fail(ctx, "LOCAL16", &.{ key, package });
    for (r.repair) |command| {
        const ran = try execute(ctx, command);
        if (ran.status == 0) continue;
        const lock = (try lockStore(ctx, scope, dir)) orelse return fail(ctx, "LOCAL15", &.{ key, package, dir, strerror(sys.errno()) });
        defer lock.release();
        var now_r = switch (try readRecord(ctx, path)) {
            .record => |x| x,
            else => r,
        };
        now_r.repairs_failed += 1;
        now_r.generation += 1;
        now_r.last_repair = .{ .time = try nowIso(ctx.a), .command = command, .status = ran.status, .output = ran.output };
        const mode: c_uint = if (scope == .person) 0o600 else 0o644;
        if (!try writeFileAtomic(ctx.a, dir, name, try recordJson(ctx, now_r), mode)) {
            return fail(ctx, "LOCAL15", &.{ key, package, dir, strerror(sys.errno()) });
        }
        const status = try std.fmt.allocPrint(ctx.a, "{d}", .{ran.status});
        const joined = try std.mem.join(ctx.a, " ", command);
        try journalEvent(ctx, "repair-failed", "LOCAL14", &.{ key, package, joined, status }, "3", scope, now_r, path);
        try setErr(ctx, "LOCAL14", &.{ key, package, joined, status });
        return ran.status;
    }
    const lock = (try lockStore(ctx, scope, dir)) orelse return fail(ctx, "LOCAL28", &.{ key, package, dir, strerror(sys.errno()) });
    defer lock.release();
    // a repair command that is the package's own step (sparky-stereo-time, sparky-stereo-boot repair) keeps the
    // problem again itself when it still fails, and may exit 0: then it is not repaired
    switch (try readRecord(ctx, path)) {
        .record => |after| if (after.kept_ns != r.kept_ns or !std.mem.eql(u8, after.time, r.time)) {
            var again = after;
            again.repairs_failed += 1;
            again.generation += 1;
            const joined = try std.mem.join(ctx.a, " ", r.repair[r.repair.len - 1]);
            again.last_repair = .{ .time = try nowIso(ctx.a), .command = r.repair[r.repair.len - 1], .status = 0, .output = "" };
            const mode: c_uint = if (scope == .person) 0o600 else 0o644;
            if (!try writeFileAtomic(ctx.a, dir, name, try recordJson(ctx, again), mode)) {
                return fail(ctx, "LOCAL15", &.{ key, package, dir, strerror(sys.errno()) });
            }
            try journalEvent(ctx, "repair-failed", "LOCAL62", &.{ key, package, joined }, "3", scope, again, path);
            try setErr(ctx, "LOCAL62", &.{ key, package, joined });
            return 1;
        },
        else => {},
    }
    if (sys.unlink(try z(ctx.a, path)) != 0 and sys.errno() != sys.ENOENT) {
        return fail(ctx, "LOCAL28", &.{ key, package, dir, strerror(sys.errno()) });
    }
    try journalEvent(ctx, "repaired", "LOCAL13", &.{ key, package }, "6", scope, r, path);
    return 0;
}

// Every problem of PACKAGE goes from each store the caller can write (root: the machine's and this boot's; a person:
// their own): its package was removed, and a problem of a package that is gone cannot be repaired by it. The number
pub fn clearAll(ctx: *Ctx, package: []const u8) Failure!usize {
    if (!validPackage(package)) return fail(ctx, "LOCAL30", &.{package});
    var n: usize = 0;
    const scopes: []const Scope = if (ctx.euid == 0) &.{ .machine, .boot } else &.{.person};
    for (scopes) |scope| {
        const dir = (try storeDir(ctx, scope)) orelse continue;
        const d = sys.opendir(try z(ctx.a, dir)) orelse continue;
        defer _ = sys.closedir(d);
        const prefix = try cat(ctx.a, &.{ package, "_" });
        var keys: std.ArrayList([]const u8) = .empty;
        while (sys.readdir(d)) |e| {
            const f = std.mem.sliceTo(&e.name, 0);
            if (!std.mem.startsWith(u8, f, prefix) or !std.mem.endsWith(u8, f, ".json")) continue;
            switch (try readRecord(ctx, try cat(ctx.a, &.{ dir, "/", f }))) {
                .record => |r| if (std.mem.eql(u8, r.package, package)) try keys.append(ctx.a, r.key),
                else => {},
            }
        }
        for (keys.items) |k| {
            if (try clear(ctx, scope, package, k)) n += 1;
        }
    }
    return n;
}

// dpkg's own list of PACKAGE's files: a package that has none is not installed (null when dpkg's database is not
// there, as in a bare build root: then nothing is judged)
fn installed(ctx: *Ctx, package: []const u8) Failure!?bool {
    const info = try cat(ctx.a, &.{ ctx.root, "/var/lib/dpkg/info" });
    if (sys.access(try z(ctx.a, try cat(ctx.a, &.{ ctx.root, "/var/lib/dpkg/status" })), 0) != 0) return null;
    for ([_][]const u8{ "", ":amd64", ":i386", ":all" }) |arch| {
        if (sys.access(try z(ctx.a, try cat(ctx.a, &.{ info, "/", package, arch, ".list" })), 0) == 0) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------------------------------------------
// Hide and show (the person's own view)

fn hideDir(ctx: *Ctx) Failure!?[]const u8 {
    const d = (try personDir(ctx)) orelse return null;
    return try cat(ctx.a, &.{ d, "/.hidden" });
}

fn hideName(ctx: *Ctx, scope: Scope, package: []const u8, key: []const u8) Failure![]const u8 {
    return cat(ctx.a, &.{ @tagName(scope), "_", package, "_", try encodeKey(ctx.a, key) });
}

fn personName() []const u8 {
    if (sys.getpwuid(sys.getuid())) |pw| return std.mem.span(pw.name);
    return "?";
}

pub fn hide(ctx: *Ctx, scope: Scope, package: []const u8, key: []const u8) Failure!void {
    try checkNames(ctx, package, key);
    const dir = try needDir(ctx, scope, package, key);
    const path = try cat(ctx.a, &.{ dir, "/", try recordName(ctx, package, key) });
    const r = switch (try readRecord(ctx, path)) {
        .missing => return fail(ctx, "LOCAL18", &.{ key, package }),
        .unreadable => |e| return fail(ctx, "LOCAL25", &.{try cat(ctx.a, &.{ path, ": ", e })}),
        .record => |x| x,
    };
    const hd = (try hideDir(ctx)) orelse return fail(ctx, "LOCAL15", &.{ key, package, "~/.local/state", "no home folder" });
    if (!try ensureDir(ctx.a, hd, 0o700, true)) return fail(ctx, "LOCAL15", &.{ key, package, hd, strerror(sys.errno()) });
    var w = Writer{ .a = ctx.a };
    try w.open("{");
    try w.key("id");
    try w.str(r.id);
    try w.key("generation");
    try w.int(r.generation);
    try w.key("time");
    try w.str(try nowIso(ctx.a));
    try w.close("}");
    try w.raw("\n");
    if (!try writeFileAtomic(ctx.a, hd, try hideName(ctx, scope, package, key), w.out.items, 0o600)) {
        return fail(ctx, "LOCAL15", &.{ key, package, hd, strerror(sys.errno()) });
    }
    try journalEvent(ctx, "hidden", "LOCAL19", &.{ key, package, personName() }, "6", scope, r, path);
}

pub fn show(ctx: *Ctx, scope: Scope, package: []const u8, key: []const u8) Failure!void {
    try checkNames(ctx, package, key);
    const hd = (try hideDir(ctx)) orelse return;
    const file = try cat(ctx.a, &.{ hd, "/", try hideName(ctx, scope, package, key) });
    if (sys.unlink(try z(ctx.a, file)) != 0 and sys.errno() != sys.ENOENT) {
        return fail(ctx, "LOCAL28", &.{ key, package, hd, strerror(sys.errno()) });
    }
    const r = Record{ .package = package, .key = key, .message = "" };
    try journalEvent(ctx, "shown", "LOCAL20", &.{ key, package, personName() }, "6", scope, r, "");
}

pub fn isHidden(ctx: *Ctx, scope: Scope, r: Record) Failure!bool {
    const hd = (try hideDir(ctx)) orelse return false;
    const text = readFile(ctx.a, try cat(ctx.a, &.{ hd, "/", try hideName(ctx, scope, r.package, r.key) })) catch return false;
    const v = std.json.parseFromSliceLeaky(Value, ctx.a, text, .{}) catch return false;
    if (v != .object) return false;
    const id = fieldStr(v.object, "id") orelse return false;
    const generation = fieldInt(v.object, "generation") orelse return false;
    return std.mem.eql(u8, id, r.id) and generation == r.generation;
}

// ---------------------------------------------------------------------------------------------------------------
// systemd's own state of a unit

fn systemBus(ctx: *Ctx) ?*anyopaque {
    if (!ctx.bus_tried) {
        ctx.bus_tried = true;
        var b: ?*anyopaque = null;
        if (sys.sd_bus_open_system(&b) >= 0) ctx.bus = b;
    }
    return ctx.bus;
}

pub fn unitProperty(ctx: *Ctx, unit: []const u8, property: []const u8) Failure!?[]const u8 {
    const bus = systemBus(ctx) orelse return null;
    var path: ?[*:0]u8 = null;
    if (sys.sd_bus_path_encode("/org/freedesktop/systemd1/unit", try z(ctx.a, unit), &path) < 0) return null;
    defer sys.free(path);
    var err = sys.BusError{};
    defer sys.sd_bus_error_free(&err);
    var out: ?[*:0]u8 = null;
    if (sys.sd_bus_get_property_string(bus, "org.freedesktop.systemd1", path.?, "org.freedesktop.systemd1.Unit", try z(ctx.a, property), &err, &out) < 0) return null;
    defer sys.free(out);
    return try ctx.a.dupe(u8, std.mem.span(out.?));
}

fn journalLines(ctx: *Ctx, invocation: ?[]const u8, unit: []const u8, max: usize) Failure![]const u8 {
    var j: ?*anyopaque = null;
    const r = sys.sd_journal_open(&j, sys.SD_JOURNAL_LOCAL_ONLY | sys.SD_JOURNAL_SYSTEM);
    if (r < 0) return cat(ctx.a, &.{ "(the system journal could not be read: ", strerror(-r), ")" });
    defer sys.sd_journal_close(j);
    const jj = j.?;
    const matches = if (invocation) |inv|
        [2][]const u8{ try cat(ctx.a, &.{ "_SYSTEMD_INVOCATION_ID=", inv }), try cat(ctx.a, &.{ "INVOCATION_ID=", inv }) }
    else
        [2][]const u8{ try cat(ctx.a, &.{ "_SYSTEMD_UNIT=", unit }), try cat(ctx.a, &.{ "UNIT=", unit }) };
    _ = sys.sd_journal_add_match(jj, matches[0].ptr, matches[0].len);
    _ = sys.sd_journal_add_disjunction(jj);
    _ = sys.sd_journal_add_match(jj, matches[1].ptr, matches[1].len);
    _ = sys.sd_journal_seek_tail(jj);
    var lines: std.ArrayList([]const u8) = .empty;
    while (lines.items.len < max and sys.sd_journal_previous(jj) > 0) {
        var data: ?[*]const u8 = null;
        var len: usize = 0;
        if (sys.sd_journal_get_data(jj, "MESSAGE", &data, &len) < 0) continue;
        const s = data.?[0..len];
        try lines.append(ctx.a, try ctx.a.dupe(u8, if (std.mem.startsWith(u8, s, "MESSAGE=")) s[8..] else s));
    }
    std.mem.reverse([]const u8, lines.items);
    return std.mem.join(ctx.a, "\n", lines.items);
}

// The handler of every failed system service (sparky-stereo-problems-failed@.service, from the top-level drop-in
// service.d/50-sparky-stereo-problems.conf, systemd.unit(5) "Top level drop-ins with template units"): the failure is
// kept for this boot with the service's own last lines, and its repair is systemd's restart
pub fn serviceFailed(ctx: *Ctx, unit_arg: ?[]const u8) Failure!Record {
    var unit = env("MONITOR_UNIT") orelse unit_arg orelse return fail(ctx, "LOCAL31", &.{ "", engine_package });
    if (std.mem.indexOfScalar(u8, unit, '.') == null) unit = try cat(ctx.a, &.{ unit, ".service" });
    const result = env("MONITOR_SERVICE_RESULT") orelse "";
    const status = env("MONITOR_EXIT_STATUS") orelse "";
    var reason: std.json.Array = .init(ctx.a);
    const simple = [_]struct { []const u8, []const u8 }{
        .{ "timeout", "LOCAL8" },      .{ "start-limit-hit", "LOCAL9" },
        .{ "oom-kill", "LOCAL10" },    .{ "watchdog", "LOCAL11" },
    };
    if (std.mem.eql(u8, result, "exit-code")) {
        try reason.append(.{ .string = "LOCAL5" });
        try reason.append(.{ .string = status });
    } else if (std.mem.eql(u8, result, "signal")) {
        try reason.append(.{ .string = "LOCAL6" });
        try reason.append(.{ .string = status });
    } else if (std.mem.eql(u8, result, "core-dump")) {
        try reason.append(.{ .string = "LOCAL7" });
        try reason.append(.{ .string = status });
    } else {
        for (simple) |s| {
            if (std.mem.eql(u8, result, s[0])) {
                try reason.append(.{ .string = s[1] });
                break;
            }
        } else {
            try reason.append(.{ .string = "LOCAL12" });
            try reason.append(.{ .string = if (result.len > 0) result else "unknown" });
        }
    }
    const description = (try unitProperty(ctx, unit, "Description")) orelse unit;
    const args = try ctx.a.alloc(Value, 3);
    args[0] = .{ .string = description };
    args[1] = .{ .string = unit };
    args[2] = .{ .array = reason };
    const restart = try ctx.a.alloc([]const []const u8, 1);
    const cmd = try ctx.a.alloc([]const u8, 3);
    cmd[0] = "systemctl";
    cmd[1] = "restart";
    cmd[2] = unit;
    restart[0] = cmd;
    const r = Record{
        .package = engine_package,
        .key = unit,
        .message = "LOCAL4",
        .args = args,
        .severity = .failed,
        .status = std.fmt.parseInt(i64, status, 10) catch null,
        .output = try journalLines(ctx, env("MONITOR_INVOCATION_ID"), unit, 20),
        .repair = restart,
        .unit = unit,
    };
    return keep(ctx, .boot, r);
}

// ---------------------------------------------------------------------------------------------------------------
// list

pub const Listed = struct {
    scope: Scope,
    file: []const u8,
    record: ?Record,
    unreadable: []const u8 = "",
    hidden: bool = false,
};

fn lessByFirst(_: void, x: Listed, y: Listed) bool {
    const fx = if (x.record) |r| r.first else "";
    const fy = if (y.record) |r| r.first else "";
    return std.mem.order(u8, fx, fy) == .lt;
}

// Every kept problem, the machine's, this boot's and the person's, oldest first; a record that cannot be read is
// listed as such, never left out. A failed service that systemd no longer has as failed is over and goes
pub fn collect(ctx: *Ctx, package: ?[]const u8) Failure![]Listed {
    var out: std.ArrayList(Listed) = .empty;
    var names: std.StringHashMapUnmanaged(void) = .empty;
    for ([_]Scope{ .machine, .boot, .person }) |scope| {
        const dir = (try storeDir(ctx, scope)) orelse continue;
        const d = sys.opendir(try z(ctx.a, dir)) orelse {
            if (sys.errno() != sys.ENOENT) try out.append(ctx.a, .{ .scope = scope, .file = dir, .record = null, .unreadable = strerror(sys.errno()) });
            continue;
        };
        defer _ = sys.closedir(d);
        var files: std.ArrayList([]const u8) = .empty;
        while (sys.readdir(d)) |e| {
            const n = std.mem.sliceTo(&e.name, 0);
            if (n.len == 0 or n[0] == '.' or !std.mem.endsWith(u8, n, ".json")) continue;
            try files.append(ctx.a, try ctx.a.dupe(u8, n));
        }
        std.mem.sort([]const u8, files.items, {}, struct {
            fn lt(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.order(u8, x, y) == .lt;
            }
        }.lt);
        for (files.items) |n| {
            const path = try cat(ctx.a, &.{ dir, "/", n });
            switch (try readRecord(ctx, path)) {
                .missing => {},
                .unreadable => |e| try out.append(ctx.a, .{ .scope = scope, .file = path, .record = null, .unreadable = e }),
                .record => |r| {
                    if (package) |p| if (!std.mem.eql(u8, p, r.package)) continue;
                    // the problem of a package that is not installed any more is over (its postrm clears the
                    // machine's; this clears what it could not reach)
                    if (!std.mem.eql(u8, r.package, engine_package) and (try installed(ctx, r.package)) == false) {
                        if (scope == .person or ctx.euid == 0) {
                            if (sys.unlink(try z(ctx.a, path)) == 0) {
                                try journalEvent(ctx, "over", "LOCAL59", &.{ r.key, r.package, r.package }, "6", scope, r, path);
                            }
                        }
                        continue;
                    }
                    if (r.unit) |u| {
                        if (try unitProperty(ctx, u, "ActiveState")) |state| {
                            if (!std.mem.eql(u8, state, "failed")) {
                                if (scope == .person or ctx.euid == 0) {
                                    if (sys.unlink(try z(ctx.a, path)) == 0) {
                                        try journalEvent(ctx, "over", "LOCAL21", &.{ r.key, r.package, u }, "6", scope, r, path);
                                    }
                                }
                                continue;
                            }
                        }
                    }
                    try names.put(ctx.a, try hideName(ctx, scope, r.package, r.key), {});
                    try out.append(ctx.a, .{ .scope = scope, .file = path, .record = r, .hidden = try isHidden(ctx, scope, r) });
                },
            }
        }
    }
    std.mem.sort(Listed, out.items, {}, lessByFirst);
    // the person's hide marks of problems that are over go with them
    if (package == null) {
        if (try hideDir(ctx)) |hd| {
            if (sys.opendir(try z(ctx.a, hd))) |d| {
                defer _ = sys.closedir(d);
                while (sys.readdir(d)) |e| {
                    const n = std.mem.sliceTo(&e.name, 0);
                    if (n.len == 0 or n[0] == '.') continue;
                    if (!names.contains(n)) _ = sys.unlink(try z(ctx.a, try cat(ctx.a, &.{ hd, "/", n })));
                }
            }
        }
    }
    return out.items;
}

pub fn listJson(ctx: *Ctx, package: ?[]const u8, lang: ?[]const u8) Failure![]const u8 {
    const items = try collect(ctx, package);
    var w = Writer{ .a = ctx.a };
    try w.open("[");
    for (items) |item| {
        try w.open("{");
        try w.key("scope");
        try w.str(@tagName(item.scope));
        try w.key("file");
        try w.str(item.file);
        if (item.record) |r| {
            try writeRecordFields(&w, ctx, r);
            const shown = try renderRecord(ctx, r, lang);
            try w.key("title");
            try w.str(shown.title);
            try w.key("text");
            try w.str(shown.text);
            try w.key("lang");
            try w.str(shown.lang);
            try w.key("hidden");
            try w.boolean(item.hidden);
            try w.key("labels");
            try w.open("[");
            for (r.actions) |act| {
                const label = try render(ctx, r.package, act.label[0].string, act.label[1..], shown.lang);
                try w.str(label.text);
            }
            try w.close("]");
        } else {
            try w.key("unreadable");
            try w.str(item.unreadable);
        }
        try w.close("}");
    }
    try w.close("]");
    try w.raw("\n");
    return w.out.items;
}

// ---------------------------------------------------------------------------------------------------------------
// The catalog builder (package build time): a package's Sparky language files (lang/en, lang/pl ...: KEY="text",
// %s for each argument) become PACKAGE.catalog and PACKAGE.LANG.catalog

pub const SubjectRule = struct { subject: []const u8, keys: ?[]const []const u8 };

fn parseLangFile(a: Allocator, text: []const u8) Failure!struct { keys: []const []const u8, map: std.StringHashMapUnmanaged([]const u8) } {
    var keys: std.ArrayList([]const u8) = .empty;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const k = std.mem.trim(u8, line[0..eq], " \t");
        var v = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (v.len >= 2 and v[0] == '"' and v[v.len - 1] == '"') v = v[1 .. v.len - 1];
        if (!map.contains(k)) try keys.append(a, k);
        try map.put(a, k, v);
    }
    return .{ .keys = keys.items, .map = map };
}

fn placeholders(t: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i + 1 < t.len) : (i += 1) {
        if (t[i] == '%') {
            if (t[i + 1] == 's') n += 1;
            i += 1;
        }
    }
    return n;
}

fn catalogText(a: Allocator, t: []const u8) Failure![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var n: usize = 0;
    var i: usize = 0;
    while (i < t.len) : (i += 1) {
        if (t[i] == '%' and i + 1 < t.len and t[i + 1] == 's') {
            try out.print(a, "@SPARKY_ARG_{c}@", .{@as(u8, 'A') + @as(u8, @intCast(@min(n, 25)))});
            n += 1;
            i += 1;
        } else if (t[i] == '%' and i + 1 < t.len and t[i + 1] == '%') {
            try out.append(a, '%');
            i += 1;
        } else {
            try out.append(a, t[i]);
        }
    }
    return out.items;
}

fn langCode(n: []const u8) bool {
    if (n.len < 2 or n.len > 6 or n[0] == '.') return false;
    for (n) |c| if (!std.ascii.isAlphabetic(c) and c != '_') return false;
    return true;
}

// gettext .po files (a KDE program's po/LANG/DOMAIN.po, or po/LANG.po): a message is named CONTEXT|MSGID (MSGID alone
// when it has no context), its %1 to %26 are its arguments A to Z, in any order a language needs
const PoEntry = struct { ctxt: ?[]const u8, id: []const u8, plural: bool, str: []const u8, fuzzy: bool };

fn unescapePo(a: Allocator, t: []const u8) Failure![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < t.len) : (i += 1) {
        if (t[i] == '\\' and i + 1 < t.len) {
            i += 1;
            try out.append(a, switch (t[i]) {
                'n' => '\n',
                't' => '\t',
                else => t[i],
            });
        } else try out.append(a, t[i]);
    }
    return out.items;
}

fn parsePo(a: Allocator, text: []const u8) Failure![]PoEntry {
    var entries: std.ArrayList(PoEntry) = .empty;
    var blocks = std.mem.splitSequence(u8, text, "\n\n");
    while (blocks.next()) |block| {
        var e = PoEntry{ .ctxt = null, .id = "", .plural = false, .str = "", .fuzzy = false };
        var target: enum { none, ctxt, id, plural, str, other } = .none;
        var ctxt: std.ArrayList(u8) = .empty;
        var id: std.ArrayList(u8) = .empty;
        var str: std.ArrayList(u8) = .empty;
        var has_id = false;
        var lines = std.mem.splitScalar(u8, block, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (std.mem.startsWith(u8, line, "#,") and std.mem.indexOf(u8, line, "fuzzy") != null) e.fuzzy = true;
            if (line.len == 0 or line[0] == '#') continue;
            var rest = line;
            if (std.mem.startsWith(u8, line, "msgctxt ")) {
                target = .ctxt;
                e.ctxt = "";
                rest = line["msgctxt ".len..];
            } else if (std.mem.startsWith(u8, line, "msgid_plural ")) {
                target = .plural;
                e.plural = true;
                rest = line["msgid_plural ".len..];
            } else if (std.mem.startsWith(u8, line, "msgid ")) {
                target = .id;
                has_id = true;
                rest = line["msgid ".len..];
            } else if (std.mem.startsWith(u8, line, "msgstr ")) {
                target = .str;
                rest = line["msgstr ".len..];
            } else if (std.mem.startsWith(u8, line, "msgstr[")) {
                target = .other;
                continue;
            }
            if (rest.len < 2 or rest[0] != '"' or rest[rest.len - 1] != '"') continue;
            const piece = try unescapePo(a, rest[1 .. rest.len - 1]);
            switch (target) {
                .ctxt => try ctxt.appendSlice(a, piece),
                .id => try id.appendSlice(a, piece),
                .str => try str.appendSlice(a, piece),
                else => {},
            }
        }
        if (!has_id or id.items.len == 0) continue;
        if (e.ctxt != null) e.ctxt = ctxt.items;
        e.id = id.items;
        e.str = str.items;
        try entries.append(a, e);
    }
    return entries.items;
}

fn poKey(a: Allocator, e: PoEntry) Failure![]const u8 {
    return if (e.ctxt) |c| cat(a, &.{ c, "|", e.id }) else e.id;
}

// the set of %1 .. %26 a text uses
fn poPlaceholders(t: []const u8) u32 {
    var set: u32 = 0;
    var i: usize = 0;
    while (i + 1 < t.len) : (i += 1) {
        if (t[i] != '%') continue;
        var j = i + 1;
        while (j < t.len and std.ascii.isDigit(t[j])) j += 1;
        if (j > i + 1) {
            const n = std.fmt.parseInt(u32, t[i + 1 .. j], 10) catch 0;
            if (n >= 1 and n <= 26) set |= @as(u32, 1) << @intCast(n - 1);
        }
    }
    return set;
}

fn poCatalogText(a: Allocator, t: []const u8) Failure![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < t.len) : (i += 1) {
        if (t[i] == '%' and i + 1 < t.len and std.ascii.isDigit(t[i + 1])) {
            var j = i + 1;
            while (j < t.len and std.ascii.isDigit(t[j])) j += 1;
            const n = std.fmt.parseInt(u32, t[i + 1 .. j], 10) catch 0;
            if (n >= 1 and n <= 26) {
                try out.print(a, "@SPARKY_ARG_{c}@", .{@as(u8, 'A') + @as(u8, @intCast(n - 1))});
                i = j - 1;
                continue;
            }
        }
        try out.append(a, t[i]);
    }
    return out.items;
}

fn findPo(ctx: *Ctx, dir: []const u8, domain: ?[]const u8) Failure!?[]const u8 {
    if (domain) |d| {
        const p = try cat(ctx.a, &.{ dir, "/", d, ".po" });
        return if (sys.access(try z(ctx.a, p), 0) == 0) p else null;
    }
    const d = sys.opendir(try z(ctx.a, dir)) orelse return null;
    defer _ = sys.closedir(d);
    var found: ?[]const u8 = null;
    while (sys.readdir(d)) |e| {
        const n = std.mem.sliceTo(&e.name, 0);
        if (!std.mem.endsWith(u8, n, ".po")) continue;
        if (found != null) return null;
        found = try cat(ctx.a, &.{ dir, "/", n });
    }
    return found;
}

fn buildPoCatalog(ctx: *Ctx, package: []const u8, podir: []const u8, outdir: []const u8, rules: []const SubjectRule, only: ?[]const []const u8, contexts: []const []const u8, domain: ?[]const u8) Failure!usize {
    const LangPo = struct { lang: []const u8, path: []const u8 };
    var files: std.ArrayList(LangPo) = .empty;
    var pot: ?[]const u8 = null;
    if (sys.opendir(try z(ctx.a, podir))) |d| {
        defer _ = sys.closedir(d);
        while (sys.readdir(d)) |e| {
            const n = try ctx.a.dupe(u8, std.mem.sliceTo(&e.name, 0));
            if (n.len == 0 or n[0] == '.') continue;
            const full = try cat(ctx.a, &.{ podir, "/", n });
            if (std.mem.endsWith(u8, n, ".pot")) {
                pot = full;
            } else if (std.mem.endsWith(u8, n, ".po") and langCode(n[0 .. n.len - 3])) {
                try files.append(ctx.a, .{ .lang = n[0 .. n.len - 3], .path = full });
            } else if (langCode(n)) {
                if (try findPo(ctx, full, domain)) |po| try files.append(ctx.a, .{ .lang = n, .path = po });
            }
        }
    }
    if (files.items.len == 0) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ podir, ": no language file (lang/en, or gettext .po files)" })});
    std.mem.sort(LangPo, files.items, {}, struct {
        fn lt(_: void, x: LangPo, y: LangPo) bool {
            return std.mem.order(u8, x.lang, y.lang) == .lt;
        }
    }.lt);
    const source_path = pot orelse files.items[0].path;
    const source = try parsePo(ctx.a, readFile(ctx.a, source_path) catch return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ source_path, ": ", strerror(last_errno) })}));
    var english: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (source) |e| {
        if (!e.plural) try english.put(ctx.a, try poKey(ctx.a, e), e.id);
    }
    var subjects: std.StringHashMapUnmanaged([]const u8) = .empty;
    var default_subject: ?[]const u8 = null;
    for (rules) |rule| {
        if (!english.contains(rule.subject)) return fail(ctx, "LOCAL32", &.{ rule.subject, source_path });
        if (rule.keys) |ks| {
            for (ks) |k| try subjects.put(ctx.a, k, rule.subject);
        } else default_subject = rule.subject;
    }
    var selected: std.ArrayList([]const u8) = .empty;
    if (only) |ks| {
        for (ks) |k| {
            if (!english.contains(k)) return fail(ctx, "LOCAL32", &.{ k, source_path });
            try selected.append(ctx.a, k);
        }
    } else {
        for (source) |e| {
            if (e.plural) continue;
            const k = try poKey(ctx.a, e);
            var is_subject = false;
            for (rules) |rule| is_subject = is_subject or std.mem.eql(u8, rule.subject, k);
            // a subject is a message too: the engine shows it as a title of its own (renderRecord)
            if (is_subject) {
                try selected.append(ctx.a, k);
                continue;
            }
            if (contexts.len > 0) {
                const c = e.ctxt orelse continue;
                var hit = false;
                for (contexts) |prefix| hit = hit or std.mem.startsWith(u8, c, prefix);
                if (!hit) continue;
            }
            try selected.append(ctx.a, k);
        }
    }
    if (!try ensureDir(ctx.a, outdir, 0o755, true)) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ outdir, ": ", strerror(sys.errno()) })});
    var entries: usize = 0;
    var langs: std.ArrayList(LangPo) = .empty;
    try langs.append(ctx.a, .{ .lang = "en", .path = source_path });
    try langs.appendSlice(ctx.a, files.items);
    for (langs.items) |lp| {
        var map: std.StringHashMapUnmanaged(PoEntry) = .empty;
        if (!std.mem.eql(u8, lp.lang, "en")) {
            const text = readFile(ctx.a, lp.path) catch return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ lp.path, ": ", strerror(last_errno) })});
            for (try parsePo(ctx.a, text)) |e| try map.put(ctx.a, try poKey(ctx.a, e), e);
        }
        var out: std.ArrayList(u8) = .empty;
        for (selected.items) |k| {
            const subject_key = subjects.get(k) orelse default_subject orelse k;
            var body = english.get(k).?;
            var subject = english.get(subject_key).?;
            if (!std.mem.eql(u8, lp.lang, "en")) {
                // every language carries every message, translated and not fuzzy, with the same arguments
                const tr = map.get(k) orelse return fail(ctx, "LOCAL32", &.{ k, lp.path });
                if (tr.fuzzy or tr.str.len == 0) return fail(ctx, "LOCAL32", &.{ k, lp.path });
                if (poPlaceholders(tr.str) != poPlaceholders(body)) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ lp.path, ": ", k, " has other %1 .. %26 than English" })});
                body = tr.str;
                const ts = map.get(subject_key) orelse return fail(ctx, "LOCAL32", &.{ subject_key, lp.path });
                if (ts.fuzzy or ts.str.len == 0) return fail(ctx, "LOCAL32", &.{ subject_key, lp.path });
                subject = ts.str;
            }
            const text = try poCatalogText(ctx.a, body);
            if (std.mem.indexOf(u8, text, "\n-- ") != null or std.mem.startsWith(u8, text, "-- ")) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ lp.path, ": ", k, " starts a line with -- " })});
            try out.print(ctx.a, "-- {s}\nSubject: {s}\nDefined-By: {s}\nSupport: {s}\n\n{s}\n\n", .{ try messageId(ctx.a, package, k), try poCatalogText(ctx.a, subject), package, support_url, text });
            entries += 1;
        }
        const name = if (std.mem.eql(u8, lp.lang, "en")) try cat(ctx.a, &.{ package, ".catalog" }) else try cat(ctx.a, &.{ package, ".", lp.lang, ".catalog" });
        if (!try writeFileAtomic(ctx.a, outdir, name, out.items, 0o644)) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ outdir, "/", name, ": ", strerror(sys.errno()) })});
    }
    return entries;
}

pub fn buildCatalog(ctx: *Ctx, package: []const u8, langdir: []const u8, outdir: []const u8, rules: []const SubjectRule, only: ?[]const []const u8, contexts: []const []const u8, domain: ?[]const u8) Failure!usize {
    if (!validPackage(package)) return fail(ctx, "LOCAL30", &.{package});
    if (sys.access(try z(ctx.a, try cat(ctx.a, &.{ langdir, "/en" })), 0) != 0) {
        return buildPoCatalog(ctx, package, langdir, outdir, rules, only, contexts, domain);
    }
    const en_text = readFile(ctx.a, try cat(ctx.a, &.{ langdir, "/en" })) catch return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ langdir, "/en: ", strerror(last_errno) })});
    const en = try parseLangFile(ctx.a, en_text);
    var subjects: std.StringHashMapUnmanaged([]const u8) = .empty;
    var default_subject: ?[]const u8 = null;
    for (rules) |rule| {
        if (rule.keys) |ks| {
            for (ks) |k| try subjects.put(ctx.a, k, rule.subject);
        } else default_subject = rule.subject;
        if (!en.map.contains(rule.subject)) return fail(ctx, "LOCAL32", &.{ rule.subject, try cat(ctx.a, &.{ langdir, "/en" }) });
    }
    var selected: std.ArrayList([]const u8) = .empty;
    if (only) |ks| {
        for (ks) |k| {
            if (!en.map.contains(k)) return fail(ctx, "LOCAL32", &.{ k, try cat(ctx.a, &.{ langdir, "/en" }) });
            try selected.append(ctx.a, k);
        }
    } else {
        for (en.keys) |k| try selected.append(ctx.a, k);
    }
    var langs: std.ArrayList([]const u8) = .empty;
    try langs.append(ctx.a, "en");
    if (sys.opendir(try z(ctx.a, langdir))) |d| {
        defer _ = sys.closedir(d);
        while (sys.readdir(d)) |e| {
            const n = std.mem.sliceTo(&e.name, 0);
            if (!langCode(n) or std.mem.eql(u8, n, "en")) continue;
            try langs.append(ctx.a, try ctx.a.dupe(u8, n));
        }
    }
    std.mem.sort([]const u8, langs.items[1..], {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.lt);
    if (!try ensureDir(ctx.a, outdir, 0o755, true)) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ outdir, ": ", strerror(sys.errno()) })});
    var entries: usize = 0;
    for (langs.items) |lang| {
        const text = if (std.mem.eql(u8, lang, "en")) en_text else readFile(ctx.a, try cat(ctx.a, &.{ langdir, "/", lang })) catch return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ langdir, "/", lang, ": ", strerror(last_errno) })});
        const l = try parseLangFile(ctx.a, text);
        var out: std.ArrayList(u8) = .empty;
        for (selected.items) |k| {
            const subject_key = subjects.get(k) orelse default_subject orelse k;
            // a subject is a message too: the engine shows it as a title of its own (renderRecord)
            // every language carries every message, with the same arguments: a translation that lacks one fails the build
            const tmpl = l.map.get(k) orelse return fail(ctx, "LOCAL32", &.{ k, try cat(ctx.a, &.{ langdir, "/", lang }) });
            if (placeholders(tmpl) != placeholders(en.map.get(k).?)) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ langdir, "/", lang, ": ", k, " has another number of %s than English" })});
            if (placeholders(tmpl) > 26) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ langdir, "/", lang, ": ", k, " has more than 26 %s" })});
            const subject = l.map.get(subject_key) orelse return fail(ctx, "LOCAL32", &.{ subject_key, try cat(ctx.a, &.{ langdir, "/", lang }) });
            const body = try catalogText(ctx.a, tmpl);
            if (std.mem.indexOf(u8, body, "\n-- ") != null or std.mem.startsWith(u8, body, "-- ")) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ langdir, "/", lang, ": ", k, " starts a line with -- " })});
            try out.print(ctx.a, "-- {s}\nSubject: {s}\nDefined-By: {s}\nSupport: {s}\n\n{s}\n\n", .{ try messageId(ctx.a, package, k), try catalogText(ctx.a, subject), package, support_url, body });
            entries += 1;
        }
        const name = if (std.mem.eql(u8, lang, "en")) try cat(ctx.a, &.{ package, ".catalog" }) else try cat(ctx.a, &.{ package, ".", lang, ".catalog" });
        if (!try writeFileAtomic(ctx.a, outdir, name, out.items, 0o644)) return fail(ctx, "LOCAL33", &.{try cat(ctx.a, &.{ outdir, "/", name, ": ", strerror(sys.errno()) })});
    }
    return entries;
}
