// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("linux.zig").c;
const Settings = @import("settings.zig");

comptime {
    if (@sizeOf(c.struct_js_event) != 8) @compileError("Unexpected Linux joystick event size");
}

fd: c_int,
replay: bool,
bytes: [8]u8 = undefined,
used: usize = 0,
axis_seen: u6 = 0,
button_seen: u4 = 0,
axes: [6]f64 = @splat(0),
buttons: [4]bool = @splat(false),

const Joystick = @This();
pub const Read = enum { event, pending, eof };

fn isNode(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "js") or name.len < 3) return false;
    for (name[2..]) |character| {
        if (!std.ascii.isDigit(character)) return false;
    }
    return true;
}

pub fn list() void {
    const directory = c.opendir("/dev/input") orelse {
        std.debug.print("No joystick directory is accessible. Connect the Crampon and check input permissions.\n", .{});
        return;
    };
    defer _ = c.closedir(directory);

    var count: usize = 0;
    while (c.readdir(directory)) |entry| {
        const item: *const c.struct_dirent = @ptrCast(entry);
        const name = std.mem.sliceTo(@as([]const u8, &item.d_name), 0);
        if (!isNode(name)) continue;
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "/dev/input/{s}", .{name}) catch continue;
        const fd = c.open(path.ptr, c.O_RDONLY | c.O_NONBLOCK | c.O_CLOEXEC);
        if (fd < 0) {
            std.debug.print("{s} (name unavailable, check read permission)\n", .{path});
        } else {
            defer _ = c.close(fd);
            var label = [_]u8{0} ** 128;
            if (c.ioctl(fd, c.JSIOCGNAME(label.len), &label) < 0) {
                std.debug.print("{s} (name unavailable)\n", .{path});
            } else {
                std.debug.print("{s} {s}\n", .{ path, std.mem.sliceTo(@as([]const u8, &label), 0) });
            }
        }
        count += 1;
    }
    if (count == 0) std.debug.print("No joystick devices found. Connect the Crampon.\n", .{});
}

pub fn open(path: [:0]const u8, replay: bool, settings: Settings) !Joystick {
    const prefix = "/dev/input/";
    if (!replay and (!std.mem.startsWith(u8, path, prefix) or !isNode(path[prefix.len..]))) {
        return error.InvalidDevicePath;
    }
    const fd = c.open(path.ptr, c.O_RDONLY | c.O_NONBLOCK | c.O_CLOEXEC);
    if (fd < 0) return error.OpenJoystick;
    errdefer _ = c.close(fd);

    var attrs: c.struct_stat = undefined;
    if (c.fstat(fd, &attrs) != 0) return error.OpenJoystick;
    const kind = attrs.st_mode & c.S_IFMT;
    if (replay) {
        if (kind != c.S_IFREG and kind != c.S_IFIFO) return error.InvalidReplayPath;
    } else {
        var axes: u8 = 0;
        var buttons: u8 = 0;
        if (kind != c.S_IFCHR or c.ioctl(fd, c.JSIOCGAXES, &axes) < 0 or
            c.ioctl(fd, c.JSIOCGBUTTONS, &buttons) < 0) return error.InvalidDevicePath;
        for (settings.axis) |ordinal| {
            if (ordinal >= axes) return error.WrongMode;
        }
        for (settings.button) |ordinal| {
            if (ordinal >= buttons) return error.WrongMode;
        }
    }
    return .{ .fd = fd, .replay = replay };
}

pub fn ready(self: Joystick) bool {
    return self.axis_seen == 0x3f and self.button_seen == 0x0f;
}

pub fn next(self: *Joystick, settings: Settings) !Read {
    const remaining = self.bytes[self.used..];
    const length = c.read(self.fd, remaining.ptr, remaining.len);
    if (length < 0) {
        const code = std.posix.errno(length);
        if (code == .AGAIN or code == .INTR) return .pending;
        return error.ReadJoystick;
    }
    if (length == 0) {
        if (self.used != 0) return error.TruncatedRecord;
        if (!self.replay) return error.ReadJoystick;
        return .eof;
    }
    self.used += @intCast(length);
    if (self.used != self.bytes.len) return .pending;
    self.used = 0;
    const event: c.struct_js_event = @bitCast(self.bytes);
    const initial = event.type & c.JS_EVENT_INIT != 0;
    switch (event.type & ~@as(u8, c.JS_EVENT_INIT)) {
        c.JS_EVENT_AXIS => {
            if (std.mem.indexOfScalar(u8, &settings.axis, event.number)) |index| {
                var value = std.math.clamp(@as(f64, @floatFromInt(event.value)) / 32767.0, -1, 1);
                if (settings.invert[index]) value = -value;
                if (@abs(value) <= settings.deadzone[index]) value = 0;
                self.axes[index] = value;
                if (initial) self.axis_seen |= @as(u6, 1) << @as(u3, @intCast(index));
            }
        },
        c.JS_EVENT_BUTTON => {
            if (event.value != 0 and event.value != 1) return error.InvalidRecord;
            if (std.mem.indexOfScalar(u8, &settings.button, event.number)) |index| {
                self.buttons[index] = event.value == 1;
                if (initial) self.button_seen |= @as(u4, 1) << @as(u2, @intCast(index));
            }
        },
        else => return error.InvalidRecord,
    }
    return .event;
}
