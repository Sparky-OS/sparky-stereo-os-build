//! Builds the skills server: its test binaries and the `sparky-stereo-skills` program.
//! The tree decides what exists: primitives, atoms, operations and every `_kinds/<registry>/` file are found by
//! listing folders (tools/kinds_scan.zig), so adding a variant is adding a file and touching nothing here.
//! A module is given only the imports its level may use, so a lower level cannot reach a higher one at all.
//! Rank, bottom up: L6 primitive, L4 atomic, L5 executable, L3 organization, L2 context, L1 domain, surfaces.
const std = @import("std");
const scan = @import("tools/kinds_scan.zig");

const Registry = struct { name: []const u8, dir: []const u8, needs_engine: bool };
const registries = [_]Registry{
    .{ .name = "era", .dir = "surfaces/mcp/_kinds/era", .needs_engine = false },
    .{ .name = "tool", .dir = "surfaces/mcp/_kinds/tool", .needs_engine = true },
    .{ .name = "assistant", .dir = "surfaces/cli/_kinds/assistant", .needs_engine = false },
    .{ .name = "skill_kind", .dir = "compiled/L2_context/_kinds/skill_kind", .needs_engine = false },
    .{ .name = "lang", .dir = "data/_kinds/lang", .needs_engine = false },
};

const Map = std.StringHashMap(*std.Build.Module);

const Ctx = struct {
    b: *std.Build,
    io: std.Io,
    gpa: std.mem.Allocator,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    root: std.Io.Dir,

    fn module(c: Ctx, path: []const u8) *std.Build.Module {
        return c.b.createModule(.{ .root_source_file = c.b.path(path), .target = c.target, .optimize = c.optimize });
    }

    /// Every `*.zig` in `dir` as a module named `prefix` + stem, importing everything in `lower`.
    fn files(c: Ctx, dir: []const u8, prefix: []const u8, lower: []const *const Map, into: *Map) void {
        const names = scan.list(c.gpa, c.io, c.root, dir) catch @panic("cannot list a level");
        for (names) |n| {
            const m = c.module(c.b.fmt("{s}/{s}.zig", .{ dir, n }));
            for (lower) |l| addAll(m, l);
            into.put(c.b.fmt("{s}{s}", .{ prefix, n }), m) catch @panic("oom");
        }
    }
};

fn addAll(m: *std.Build.Module, from: *const Map) void {
    var it = from.iterator();
    while (it.next()) |e| m.addImport(e.key_ptr.*, e.value_ptr.*);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl } });
    const optimize = b.standardOptimizeOption(.{});
    const skills_src = b.option([]const u8, "skills-src", "checkout of the public skills tree the goldens were recorded from") orelse "";
    const c = Ctx{ .b = b, .io = b.graph.io, .gpa = b.allocator, .target = target, .optimize = optimize, .root = b.build_root.handle };

    const options = b.addOptions();
    options.addOption([]const u8, "skills_src", skills_src);
    var opts = Map.init(c.gpa);
    opts.put("options", options.createModule()) catch @panic("oom");
    var scan_map = Map.init(c.gpa);
    scan_map.put("kinds_scan", c.module("tools/kinds_scan.zig")) catch @panic("oom");
    scan_map.put("testkit", c.module("tools/testkit.zig")) catch @panic("oom");

    // L6 primitives.
    var l6 = Map.init(c.gpa);
    c.files("compiled/L6_primitive", "", &.{}, &l6);

    // L4 atoms: every folder holding atom.zig, named by its folder.
    var l4 = Map.init(c.gpa);
    {
        var d = c.root.openDir(c.io, "compiled/L4_atomic", .{ .iterate = true }) catch @panic("no L4_atomic");
        defer d.close(c.io);
        var it = d.iterate();
        while (it.next(c.io) catch @panic("scan")) |e| {
            if (e.kind != .directory) continue;
            const name = c.gpa.dupe(u8, e.name) catch @panic("oom");
            const m = c.module(b.fmt("compiled/L4_atomic/{s}/atom.zig", .{name}));
            addAll(m, &l6);
            l4.put(name, m) catch @panic("oom");
        }
    }
    var l5 = Map.init(c.gpa);
    c.files("compiled/L5_executable", "", &.{ &l6, &l4 }, &l5);
    var l3 = Map.init(c.gpa);
    c.files("compiled/L3_organization", "", &.{ &l6, &l4, &l5 }, &l3);

    // Kind registries (skill_kind first: L2 imports it).
    var regs = Map.init(c.gpa);
    var engine_map = Map.init(c.gpa); // filled below; tool kinds import the engine
    var tool_kind_modules: std.ArrayList(*std.Build.Module) = .empty;
    for (registries) |r| {
        const names = scan.list(c.gpa, c.io, c.root, r.dir) catch @panic("cannot list a registry");
        var src: std.ArrayList(u8) = .empty;
        src.appendSlice(c.gpa, "pub const names = [_][]const u8{") catch @panic("oom");
        for (names) |n| src.print(c.gpa, "\"{s}\",", .{n}) catch @panic("oom");
        src.appendSlice(c.gpa, "};\npub const all = .{") catch @panic("oom");
        for (names) |n| src.print(c.gpa, " @import(\"kind_{s}\"),", .{n}) catch @panic("oom");
        src.appendSlice(c.gpa, " };\n") catch @panic("oom");
        const wf = b.addWriteFiles();
        const gen = wf.add(b.fmt("kinds_{s}.zig", .{r.name}), src.items);
        const rm = b.createModule(.{ .root_source_file = gen, .target = target, .optimize = optimize });
        for (names) |n| {
            const km = c.module(b.fmt("{s}/{s}.zig", .{ r.dir, n }));
            addAll(km, &l6);
            if (r.needs_engine) tool_kind_modules.append(c.gpa, km) catch @panic("oom");
            rm.addImport(b.fmt("kind_{s}", .{n}), km);
        }
        regs.put(b.fmt("kinds_{s}", .{r.name}), rm) catch @panic("oom");
    }
    var ctx_regs = Map.init(c.gpa);
    ctx_regs.put("kinds_skill_kind", regs.get("kinds_skill_kind").?) catch @panic("oom");

    var l2 = Map.init(c.gpa);
    c.files("compiled/L2_context", "", &.{ &l6, &l4, &l5, &l3, &ctx_regs }, &l2);
    var l1 = Map.init(c.gpa);
    c.files("compiled/L1_domain/skills", "", &.{ &l6, &l4, &l5, &l3, &l2, &ctx_regs }, &l1);
    if (l1.get("engine")) |eng| engine_map.put("engine", eng) catch @panic("oom");
    for (tool_kind_modules.items) |km| addAll(km, &engine_map);

    // Surfaces: named modules cli_<stem> and mcp_<stem>, the doors; they see the engine, the primitives and the registries.
    var surf_base = Map.init(c.gpa);
    addAllInto(&surf_base, &l6);
    addAllInto(&surf_base, &engine_map);
    addAllInto(&surf_base, &regs);
    var surf = Map.init(c.gpa);
    c.files("surfaces/cli", "cli_", &.{&surf_base}, &surf);
    c.files("surfaces/mcp", "mcp_", &.{&surf_base}, &surf);
    {
        var it = surf.iterator();
        while (it.next()) |a| {
            var it2 = surf.iterator();
            while (it2.next()) |o| if (a.value_ptr.* != o.value_ptr.*) a.value_ptr.*.addImport(o.key_ptr.*, o.value_ptr.*);
        }
    }

    // The program.
    if (c.root.access(c.io, "surfaces/main.zig", .{})) |_| {
        const main_mod = c.module("surfaces/main.zig");
        addAll(main_mod, &surf_base);
        addAll(main_mod, &surf);
        const exe = b.addExecutable(.{ .name = "sparky-stereo-skills", .root_module = main_mod });
        b.installArtifact(exe);
    } else |_| {}

    // The tests: tests/**/<name>_test.zig, each given every module (the lint tests check the sources).
    const test_step = b.step("test-bins", "Build every test binary into zig-out/tests; scripts/run-tests.sh runs them in a container");
    var everything = Map.init(c.gpa);
    for ([_]*const Map{ &opts, &scan_map, &l6, &l4, &l5, &l3, &l2, &l1, &regs, &surf }) |m| addAllInto(&everything, m);
    var tests_listed: usize = 0;
    for ([_][]const u8{ "tests/L6_primitive", "tests/L4_atomic", "tests/L5_executable", "tests/L3_organization", "tests/L2_context", "tests/L1_domain", "tests/surfaces", "tests/lint", "tests/kinds" }) |tdir| {
        var d = c.root.openDir(c.io, tdir, .{ .iterate = true }) catch continue;
        defer d.close(c.io);
        var it = d.iterate();
        while (it.next(c.io) catch @panic("scan")) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.name, "_test.zig")) continue;
            const t = b.addTest(.{
                .name = b.fmt("{s}_{s}", .{ tdir["tests/".len..], e.name[0 .. e.name.len - ".zig".len] }),
                .root_module = c.module(b.fmt("{s}/{s}", .{ tdir, e.name })),
            });
            addAll(t.root_module, &everything);
            const inst = b.addInstallArtifact(t, .{ .dest_dir = .{ .override = .{ .custom = "tests" } } });
            test_step.dependOn(&inst.step);
            tests_listed += 1;
        }
    }
    if (tests_listed == 0) @panic("no tests found");
}

fn addAllInto(into: *Map, from: *const Map) void {
    var it = from.iterator();
    while (it.next()) |e| into.put(e.key_ptr.*, e.value_ptr.*) catch @panic("oom");
}
