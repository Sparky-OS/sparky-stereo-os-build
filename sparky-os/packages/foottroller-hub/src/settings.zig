// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("linux.zig").c;

pub const Axis = enum { x, y, left_heading, left_tilt, right_heading, right_tilt };
pub const Button = enum { left_heel, left_front, right_heel, right_front };

axis: [6]u8 = .{ 0, 1, 2, 3, 4, 5 },
invert: [6]bool = @splat(false),
deadzone: [6]f64 = @splat(0),
button: [4]u8 = .{ 0, 1, 2, 3 },
device: ?[:0]const u8 = null,
bind: c.in_addr = .{ .s_addr = 0 },

const Settings = @This();
const eql = std.mem.eql;

pub fn load(allocator: std.mem.Allocator, path: [:0]const u8) !Settings {
    const file = c.fopen(path.ptr, "r") orelse return error.OpenSettings;
    defer _ = c.fclose(file);

    var contents: [8193]u8 = undefined;
    const len = c.fread(&contents, 1, contents.len, file);
    if (c.ferror(file) != 0 or len == contents.len) return error.ReadSettings;
    if (std.mem.indexOfScalar(u8, contents[0..len], 0) != null) return error.InvalidSettings;

    var settings: Settings = .{};
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);
    var lines = std.mem.splitScalar(u8, contents[0..len], '\n');
    var number: usize = 0;
    while (lines.next()) |raw| {
        number += 1;
        const before_comment = raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len];
        const line = trim(before_comment);
        if (line.len == 0) continue;
        settings.assign(allocator, &seen, line) catch |err| {
            std.debug.print("Settings line {d}: {s}\n", .{ number, @errorName(err) });
            return error.InvalidSettings;
        };
    }
    if (!unique(&settings.axis) or !unique(&settings.button)) {
        std.debug.print("Each axis and each button must have a distinct ordinal.\n", .{});
        return error.InvalidSettings;
    }
    return settings;
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

fn unique(values: []const u8) bool {
    for (values, 0..) |value, i| {
        if (std.mem.indexOfScalar(u8, values[0..i], value) != null) return false;
    }
    return true;
}

fn assign(settings: *Settings, allocator: std.mem.Allocator, seen: *std.StringHashMapUnmanaged(void), line: []const u8) !void {
    const separator = std.mem.indexOfScalar(u8, line, '=') orelse return error.ExpectedEquals;
    const key = trim(line[0..separator]);
    const value = trim(line[separator + 1 ..]);
    const slot = try seen.getOrPut(allocator, key);
    if (slot.found_existing) return error.DuplicateKey;

    if (eql(u8, key, "device")) {
        settings.device = if (value.len == 0) null else try allocator.dupeZ(u8, value);
        return;
    }
    if (eql(u8, key, "bind_address")) {
        const address = try allocator.dupeZ(u8, value);
        defer allocator.free(address);
        if (c.inet_pton(c.AF_INET, address.ptr, &settings.bind) != 1) return error.InvalidIPv4Address;
        return;
    }
    const sep = std.mem.indexOfScalar(u8, key, '_') orelse return error.UnknownKey;
    const field = key[0..sep];
    const name = key[sep + 1 ..];
    if (eql(u8, field, "button")) {
        const button = std.meta.stringToEnum(Button, name) orelse return error.UnknownButton;
        settings.button[@intFromEnum(button)] = try std.fmt.parseInt(u8, value, 10);
        return;
    }

    const axis = std.meta.stringToEnum(Axis, name) orelse return error.UnknownAxis;
    const index = @intFromEnum(axis);
    if (eql(u8, field, "axis")) {
        settings.axis[index] = try std.fmt.parseInt(u8, value, 10);
    } else if (eql(u8, field, "invert")) {
        settings.invert[index] = if (eql(u8, value, "true")) true else if (eql(u8, value, "false")) false else return error.ExpectedBoolean;
    } else if (eql(u8, field, "deadzone")) {
        const deadzone = try std.fmt.parseFloat(f64, value);
        if (!std.math.isFinite(deadzone) or deadzone < 0 or deadzone >= 1) return error.InvalidDeadZone;
        settings.deadzone[index] = deadzone;
    } else {
        return error.UnknownKey;
    }
}
