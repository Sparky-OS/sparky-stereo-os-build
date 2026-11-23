// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("linux.zig").c;
const Settings = @import("settings.zig");
const Joystick = @import("joystick.zig");
const Gamepad = @import("gamepad.zig");
const Network = @import("network.zig");

const usage =
    \\Usage: foottroller-hub [--config FILE] [--device /dev/input/jsN]
    \\       foottroller-hub [--config FILE] --replay FILE_OR_FIFO
    \\With no selected device, lists joystick names and paths.
    \\
;

pub fn main(init: std.process.Init.Minimal) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = init.args.toSlice(allocator) catch {
        std.debug.print("Could not read command arguments. Retry with fewer arguments.\n", .{});
        std.process.exit(1);
    };
    run(allocator, args[1..]) catch |err| {
        std.debug.print("Foottroller Hub: {s}\n", .{explain(err)});
        std.process.exit(1);
    };
}

fn explain(err: anyerror) []const u8 {
    return switch (err) {
        error.BadArguments => "Invalid arguments. Run foottroller-hub --help.",
        error.OpenSettings, error.ReadSettings, error.InvalidSettings => "Could not load settings. Check the file path, permissions and key/value entries.",
        error.ChooseDevice => "Select the Crampon with --device /dev/input/jsN or set device in the settings file.",
        error.InvalidDevicePath => "The selected path is not a Linux joystick. Run without a selection to list joysticks.",
        error.OpenJoystick => "Cannot open the selected joystick. Connect the Crampon and check read permission and the selected path.",
        error.InvalidReplayPath => "Select a regular recording or a FIFO for --replay.",
        error.WrongMode => "The joystick lacks the configured Dev mode controls. Enable Dev mode and check the device and mapping.",
        error.ReadJoystick => "The joystick stopped responding. Reconnect the Crampon and restart the Hub.",
        error.TruncatedRecord, error.InvalidRecord => "Invalid joystick record. Check the selected device or recording and restart the Hub.",
        error.OpenUinput => "Cannot open /dev/uinput. Check that uinput is available and that this user can write to it.",
        error.SetupUinput => "Cannot create the virtual gamepad. Check that the kernel supports the uinput setup interface.",
        error.WriteUinput => "Cannot send events to the virtual gamepad. Check uinput and restart the Hub.",
        error.OpenSocket, error.BindSocket => "Cannot open UDP 45041. Check the configured local IPv4 address or stop the process using that port.",
        error.SendSocket, error.ReceiveSocket => "UDP 45041 failed. Check the local network and restart the Hub.",
        else => "The Hub could not initialize Linux event handling. Restart it from a terminal and check the system log.",
    };
}

fn run(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    var config: [:0]const u8 = "/etc/foottroller-hub.conf";
    var input_path: ?[:0]const u8 = null;
    var replay = false;
    var index: usize = 0;
    while (index < args.len) : (index += 2) {
        const option = args[index];
        if (std.mem.eql(u8, option, "--help")) {
            std.debug.print("{s}", .{usage});
            return;
        }
        if (index + 1 == args.len or args[index + 1].len == 0) return error.BadArguments;
        if (std.mem.eql(u8, option, "--config")) {
            config = args[index + 1];
        } else if (std.mem.eql(u8, option, "--device") or std.mem.eql(u8, option, "--replay")) {
            if (input_path != null) return error.BadArguments;
            input_path = args[index + 1];
            replay = std.mem.eql(u8, option, "--replay");
        } else return error.BadArguments;
    }
    const settings = Settings.load(allocator, config) catch |err| {
        std.debug.print("Settings file: {s}\n", .{config});
        return err;
    };
    const path = input_path orelse settings.device orelse {
        Joystick.list();
        return error.ChooseDevice;
    };

    const stop_fd = try stopSignals();
    defer _ = c.close(stop_fd);
    var input = Joystick.open(path, replay, settings) catch |err| {
        std.debug.print("Joystick path: {s}\n", .{path});
        return err;
    };
    defer _ = c.close(input.fd);

    if (!try initialize(&input, settings, stop_fd)) return;
    var network = try Network.open(settings.bind);
    defer _ = c.close(network.fd);
    var gamepad = try Gamepad.open();
    defer gamepad.close();
    try gamepad.publish(input);
    defer network.publish(Network.neutral) catch {
        std.debug.print("Cannot send a final neutral UDP state. The client will time out.\n", .{});
    };
    std.debug.print("Foottroller Hub ready on UDP 45041.\n", .{});

    try loop(&input, settings, &gamepad, &network, stop_fd);
}

fn stopSignals() !c_int {
    var mask: c.sigset_t = undefined;
    if (c.sigemptyset(&mask) != 0 or c.sigaddset(&mask, c.SIGINT) != 0 or
        c.sigaddset(&mask, c.SIGTERM) != 0 or c.sigprocmask(c.SIG_BLOCK, &mask, null) != 0)
    {
        return error.SignalSetup;
    }
    const fd = c.signalfd(-1, &mask, c.SFD_CLOEXEC | c.SFD_NONBLOCK);
    if (fd < 0) return error.SignalSetup;
    return fd;
}

fn nowMs() !i64 {
    var time: c.struct_timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &time) != 0) return error.Clock;
    return time.tv_sec * 1000 + @divFloor(time.tv_nsec, 1_000_000);
}

fn wait(fds: []c.struct_pollfd, duration_ms: c_int) !void {
    while (true) {
        const result = c.poll(fds.ptr, fds.len, duration_ms);
        if (result >= 0) return;
        if (std.posix.errno(result) != .INTR) return error.Poll;
    }
}

fn initialize(input: *Joystick, settings: Settings, stop_fd: c_int) !bool {
    const deadline = try nowMs() + 30_000;
    var fds = [_]c.struct_pollfd{
        .{ .fd = stop_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = input.fd, .events = c.POLLIN, .revents = 0 },
    };
    while (!input.ready()) {
        const remaining = deadline - try nowMs();
        if (remaining <= 0) return error.WrongMode;
        try wait(&fds, @intCast(remaining));
        if (fds[0].revents != 0) return false;
        if (fds[1].revents == 0) continue;
        if (try input.next(settings) == .eof) return error.WrongMode;
    }
    return true;
}

fn loop(input: *Joystick, settings: Settings, gamepad: *Gamepad, network: *Network, stop_fd: c_int) !void {
    var previous = Network.encode(input.*);
    var next_update = try nowMs();
    var fds = [_]c.struct_pollfd{
        .{ .fd = stop_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = input.fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = network.fd, .events = c.POLLIN, .revents = 0 },
    };
    while (true) {
        const wait_time = @max(0, next_update - try nowMs());
        try wait(&fds, @intCast(wait_time));
        if (fds[0].revents != 0) return;
        const now = try nowMs();
        network.expire(now);

        if (fds[1].revents != 0) {
            for (0..64) |_| {
                switch (try input.next(settings)) {
                    .event => {},
                    .pending => break,
                    .eof => return,
                }
                try gamepad.publish(input.*);
                const packet = Network.encode(input.*);
                if (!std.mem.eql(u8, &packet, &previous)) {
                    try network.publish(packet);
                    previous = packet;
                }
            }
        }
        if (fds[2].revents != 0) try network.receive(now, previous);
        if (now >= next_update) {
            try network.publish(previous);
            next_update = now + Network.update_interval_ms;
        }
    }
}
