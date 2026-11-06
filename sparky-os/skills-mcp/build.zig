//! Builds the skills server's tests (and, from milestone 2b, its program).
//! The tree decides what exists: atoms are found by listing `compiled/L4_atomic/`, kind files by listing each
//! `_kinds/<registry>/` folder (tools/kinds_scan.zig), so adding a variant is adding a file and touching nothing here.
//! A module is given only the imports its level may use, so a lower level cannot reach a higher one at all.
const std = @import("std");
const scan = @import("tools/kinds_scan.zig");

const Registry = struct { name: []const u8, dir: []const u8 };
const registries = [_]Registry{
    .{ .name = "era", .dir = "surfaces/mcp/_kinds/era" },
    .{ .name = "tool", .dir = "surfaces/mcp/_kinds/tool" },
    .{ .name = "assistant", .dir = "surfaces/cli/_kinds/assistant" },
    .{ .name = "skill_kind", .dir = "compiled/L2_context/_kinds/skill_kind" },
    .{ .name = "lang", .dir = "data/_kinds/lang" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl } });
    const optimize = b.standardOptimizeOption(.{});
    const skills_src = b.option([]const u8, "skills-src", "checkout of the public skills tree the goldens were recorded from") orelse "";
    const io = b.graph.io;
    const gpa = b.allocator;

    const options = b.addOptions();
    options.addOption([]const u8, "skills_src", skills_src);
    const opts_mod = options.createModule();

    const test_step = b.step("test-bins", "Build every test binary into zig-out/tests; scripts/run-tests.sh runs them in a container");
    const root_dir = b.build_root.handle;

    // L6 primitives: every .zig file in the folder, imported by its file name.
    var l6 = std.StringHashMap(*std.Build.Module).init(gpa);
    const prim_names = scan.list(gpa, io, root_dir, "compiled/L6_primitive") catch @panic("cannot list L6_primitive");
    for (prim_names) |n| {
        const m = b.createModule(.{
            .root_source_file = b.path(b.fmt("compiled/L6_primitive/{s}.zig", .{n})),
            .target = target,
            .optimize = optimize,
        });
        l6.put(n, m) catch @panic("oom");
    }

    // L4 atoms: every folder holding atom.zig, imported by its folder name; imports allowed: L6 only.
    var atoms = std.StringHashMap(*std.Build.Module).init(gpa);
    {
        var d = root_dir.openDir(io, "compiled/L4_atomic", .{ .iterate = true }) catch @panic("no L4_atomic");
        defer d.close(io);
        var it = d.iterate();
        while (it.next(io) catch @panic("scan")) |e| {
            if (e.kind != .directory) continue;
            const name = gpa.dupe(u8, e.name) catch @panic("oom");
            const m = b.createModule(.{
                .root_source_file = b.path(b.fmt("compiled/L4_atomic/{s}/atom.zig", .{name})),
                .target = target,
                .optimize = optimize,
            });
            var pit = l6.iterator();
            while (pit.next()) |p| m.addImport(p.key_ptr.*, p.value_ptr.*);
            atoms.put(name, m) catch @panic("oom");
        }
    }

    // L5 operations: every .zig file in the folder, imported by its file name; imports allowed: L4 atoms and L6.
    var ops = std.StringHashMap(*std.Build.Module).init(gpa);
    for (scan.list(gpa, io, root_dir, "compiled/L5_executable") catch @panic("cannot list L5_executable")) |n| {
        const m = b.createModule(.{
            .root_source_file = b.path(b.fmt("compiled/L5_executable/{s}.zig", .{n})),
            .target = target,
            .optimize = optimize,
        });
        var pit = l6.iterator();
        while (pit.next()) |p| m.addImport(p.key_ptr.*, p.value_ptr.*);
        var ait = atoms.iterator();
        while (ait.next()) |a| m.addImport(a.key_ptr.*, a.value_ptr.*);
        ops.put(n, m) catch @panic("oom");
    }

    // Kind registries: one generated module per registry, one module per kind file.
    const wf = b.addWriteFiles();
    var regs = std.StringHashMap(*std.Build.Module).init(gpa);
    var kind_lists = std.StringHashMap([]const []const u8).init(gpa);
    for (registries) |r| {
        const names = scan.list(gpa, io, root_dir, r.dir) catch @panic("cannot list a registry");
        kind_lists.put(r.name, names) catch @panic("oom");
        var src: std.ArrayList(u8) = .empty;
        src.appendSlice(gpa, "pub const names = [_][]const u8{") catch @panic("oom");
        for (names) |n| src.print(gpa, "\"{s}\",", .{n}) catch @panic("oom");
        src.appendSlice(gpa, "};\npub const all = .{") catch @panic("oom");
        for (names) |n| src.print(gpa, " @import(\"kind_{s}\"),", .{n}) catch @panic("oom");
        src.appendSlice(gpa, " };\n") catch @panic("oom");
        const gen = wf.add(b.fmt("kinds_{s}.zig", .{r.name}), src.items);
        const rm = b.createModule(.{ .root_source_file = gen, .target = target, .optimize = optimize });
        for (names) |n| {
            const km = b.createModule(.{
                .root_source_file = b.path(b.fmt("{s}/{s}.zig", .{ r.dir, n })),
                .target = target,
                .optimize = optimize,
            });
            rm.addImport(b.fmt("kind_{s}", .{n}), km);
        }
        regs.put(r.name, rm) catch @panic("oom");
    }

    // The tests: tests/**/<name>_test.zig, each given the atoms, the registries, the options and the scanner.
    const scan_mod = b.createModule(.{ .root_source_file = b.path("tools/kinds_scan.zig"), .target = target, .optimize = optimize });
    var tests_listed: usize = 0;
    for ([_][]const u8{ "tests/L6_primitive", "tests/L4_atomic", "tests/L5_executable", "tests/surfaces", "tests/lint", "tests/kinds" }) |tdir| {
        var d = root_dir.openDir(io, tdir, .{ .iterate = true }) catch continue;
        defer d.close(io);
        var it = d.iterate();
        while (it.next(io) catch @panic("scan")) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.name, "_test.zig")) continue;
            const t = b.addTest(.{
                .name = b.fmt("{s}_{s}", .{ tdir["tests/".len..], e.name[0 .. e.name.len - ".zig".len] }),
                .root_module = b.createModule(.{
                    .root_source_file = b.path(b.fmt("{s}/{s}", .{ tdir, e.name })),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            const tm = t.root_module;
            tm.addImport("options", opts_mod);
            tm.addImport("kinds_scan", scan_mod);
            var pit = l6.iterator();
            while (pit.next()) |p| tm.addImport(p.key_ptr.*, p.value_ptr.*);
            var ait = atoms.iterator();
            while (ait.next()) |a| tm.addImport(a.key_ptr.*, a.value_ptr.*);
            var oit = ops.iterator();
            while (oit.next()) |o| tm.addImport(o.key_ptr.*, o.value_ptr.*);
            var rit = regs.iterator();
            while (rit.next()) |r| tm.addImport(b.fmt("kinds_{s}", .{r.key_ptr.*}), r.value_ptr.*);
            const inst = b.addInstallArtifact(t, .{ .dest_dir = .{ .override = .{ .custom = "tests" } } });
            test_step.dependOn(&inst.step);
            tests_listed += 1;
        }
    }
    if (tests_listed == 0) @panic("no tests found");
    test_step.dependOn(&wf.step);
}
