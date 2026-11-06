//! L5 operation: run one listed command. No shell: the argument list is built from the skill's own argv with each
//! slot replaced by a value that matches its class; the child gets only LANG, HOME, XDG_* and a fixed PATH.
//! The gate (command_gate) has decided before this is called; this refuses a root process and an unlisted id by itself.
const std = @import("std");
const proc = @import("proc");
const slot_class = @import("slot_class");
const command_spec = @import("command_spec");

pub const Value = struct { name: []const u8, value: []const u8 };

pub const Outcome = struct {
    exit_code: ?u8,
    stdout: []const u8,
    stderr: []const u8,
    timed_out: bool,
    /// Whether the skill's `expect` matched (true when it states none).
    expected: bool,
};

pub const Error = error{ NotListed, BadSlot, MissingSlot, RunningAsRoot } || anyerror;

pub fn substitute(arena: std.mem.Allocator, cmd: command_spec.Command, values: []const Value) Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    for (cmd.argv) |tok| {
        if (tok.len >= 3 and tok[0] == '{' and tok[tok.len - 1] == '}') {
            const name = tok[1 .. tok.len - 1];
            var class: ?[]const u8 = null;
            for (cmd.slots) |s| if (std.mem.eql(u8, s.name, name)) {
                class = s.class;
            };
            var val: ?[]const u8 = null;
            for (values) |v| if (std.mem.eql(u8, v.name, name)) {
                val = v.value;
            };
            const c = class orelse return error.BadSlot;
            const v = val orelse return error.MissingSlot;
            if (!slot_class.matches(c, v)) return error.BadSlot;
            try argv.append(arena, v);
        } else try argv.append(arena, tok);
    }
    return argv.items;
}

/// `home` and `lang` and `xdg` come from the caller's environment; nothing else is passed on.
pub fn run(arena: std.mem.Allocator, io: std.Io, cmds: []const command_spec.Command, id: []const u8, values: []const Value, env_in: *const std.process.Environ.Map) Error!Outcome {
    if (std.os.linux.geteuid() == 0) return error.RunningAsRoot;
    var cmd: ?command_spec.Command = null;
    for (cmds) |c| if (std.mem.eql(u8, c.id, id)) {
        cmd = c;
    };
    const c = cmd orelse return error.NotListed;
    const argv = try substitute(arena, c, values);
    var env = std.process.Environ.Map.init(arena);
    try env.put("PATH", "/usr/bin:/bin");
    var it = env_in.iterator();
    while (it.next()) |kv| {
        const k = kv.key_ptr.*;
        if (std.mem.eql(u8, k, "LANG") or std.mem.eql(u8, k, "HOME") or std.mem.startsWith(u8, k, "XDG_")) try env.put(k, kv.value_ptr.*);
    }
    const r = try proc.run(arena, io, .{ .argv = argv, .env = &env });
    var ok = !r.timed_out;
    if (c.expect_exit) |want| ok = ok and r.exit_code != null and r.exit_code.? == want;
    if (c.expect_contains.len > 0) ok = ok and std.mem.indexOf(u8, r.stdout, c.expect_contains) != null;
    return .{ .exit_code = r.exit_code, .stdout = r.stdout, .stderr = r.stderr, .timed_out = r.timed_out, .expected = ok };
}
