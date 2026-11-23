// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("linux.zig").c;
const Joystick = @import("joystick.zig");

const name = "Foottroller Hub Gamepad";
const axes = [_]u16{ c.ABS_X, c.ABS_Y };
const buttons = [_]u16{ c.BTN_SOUTH, c.BTN_EAST, c.BTN_NORTH, c.BTN_WEST };
const limit = 32767;

fd: c_int,
values: [2]i32 = @splat(0),
pressed: [4]bool = @splat(false),

const Gamepad = @This();

pub fn open() !Gamepad {
    const fd = c.open("/dev/uinput", c.O_WRONLY | c.O_NONBLOCK | c.O_CLOEXEC);
    if (fd < 0) return error.OpenUinput;
    errdefer _ = c.close(fd);

    try ioctl(fd, c.UI_SET_EVBIT, @as(c_int, c.EV_ABS));
    try ioctl(fd, c.UI_SET_EVBIT, @as(c_int, c.EV_KEY));
    for (axes) |axis| {
        try ioctl(fd, c.UI_SET_ABSBIT, @as(c_int, axis));
        var abs = std.mem.zeroes(c.struct_uinput_abs_setup);
        abs.code = axis;
        abs.absinfo.minimum = -limit;
        abs.absinfo.maximum = limit;
        try ioctl(fd, c.UI_ABS_SETUP, &abs);
    }
    for (buttons) |button| try ioctl(fd, c.UI_SET_KEYBIT, @as(c_int, button));

    var setup = std.mem.zeroes(c.struct_uinput_setup);
    setup.id.bustype = c.BUS_VIRTUAL;
    setup.id.version = 1;
    @memcpy(setup.name[0..name.len], name);
    try ioctl(fd, c.UI_DEV_SETUP, &setup);
    try ioctl(fd, c.UI_DEV_CREATE, @as(c_int, 0));
    errdefer _ = c.ioctl(fd, c.UI_DEV_DESTROY, @as(c_int, 0));

    var sysname = [_]u8{0} ** 64;
    try ioctl(fd, c.UI_GET_SYSNAME(sysname.len), &sysname);
    std.debug.print("Virtual gamepad: {s} ({s})\n", .{ name, std.mem.sliceTo(@as([]const u8, &sysname), 0) });
    return .{ .fd = fd };
}

fn ioctl(fd: c_int, request: c_ulong, argument: anytype) !void {
    if (c.ioctl(fd, request, argument) < 0) return error.SetupUinput;
}

pub fn close(self: Gamepad) void {
    if (c.ioctl(self.fd, c.UI_DEV_DESTROY, @as(c_int, 0)) < 0) {
        std.debug.print("Could not explicitly destroy the virtual gamepad. Closing its descriptor.\n", .{});
    }
    _ = c.close(self.fd);
}

fn event(event_type: u16, code: u16, value: i32) c.struct_input_event {
    var result = std.mem.zeroes(c.struct_input_event);
    result.type = event_type;
    result.code = code;
    result.value = value;
    return result;
}

pub fn publish(self: *Gamepad, input: Joystick) !void {
    var records: [7]c.struct_input_event = undefined;
    var count: usize = 0;
    for (axes, 0..) |axis, index| {
        const value: i32 = @intFromFloat(@round(input.axes[index] * limit));
        if (value == self.values[index]) continue;
        self.values[index] = value;
        records[count] = event(c.EV_ABS, axis, value);
        count += 1;
    }
    for (buttons, input.buttons, 0..) |button, pressed, index| {
        if (self.pressed[index] == pressed) continue;
        self.pressed[index] = pressed;
        records[count] = event(c.EV_KEY, button, @intFromBool(pressed));
        count += 1;
    }
    if (count == 0) return;
    records[count] = event(c.EV_SYN, c.SYN_REPORT, 0);
    const bytes = std.mem.sliceAsBytes(records[0 .. count + 1]);
    while (true) {
        const written = c.write(self.fd, bytes.ptr, bytes.len);
        if (written == bytes.len) return;
        if (std.posix.errno(written) != .INTR) return error.WriteUinput;
    }
}
