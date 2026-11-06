//! L6 primitive: run one program from an argument list, never through a shell, with a reduced environment,
//! a time limit and an output limit. Nothing runs unless a caller above the gate asks.
const std = @import("std");

pub const Result = struct {
    exit_code: ?u8,
    stdout: []u8,
    stderr: []u8,
    timed_out: bool,
};

pub const Options = struct {
    argv: []const []const u8,
    env: *const std.process.Environ.Map,
    timeout_ms: i64 = 30_000,
    max_output: usize = 16 * 1024,
};

pub fn run(gpa: std.mem.Allocator, io: std.Io, o: Options) !Result {
    const r = std.process.run(gpa, io, .{
        .argv = o.argv,
        .environ_map = o.env,
        .stdout_limit = .limited(o.max_output),
        .stderr_limit = .limited(o.max_output),
        .timeout = .{ .duration = .{ .raw = .fromMilliseconds(o.timeout_ms), .clock = .awake } },
    }) catch |e| switch (e) {
        error.Timeout => return .{ .exit_code = null, .stdout = &.{}, .stderr = &.{}, .timed_out = true },
        else => return e,
    };
    const code: ?u8 = switch (r.term) {
        .exited => |c| c,
        else => null,
    };
    return .{ .exit_code = code, .stdout = r.stdout, .stderr = r.stderr, .timed_out = false };
}
