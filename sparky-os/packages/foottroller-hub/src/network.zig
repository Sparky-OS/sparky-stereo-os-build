// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("linux.zig").c;
const Joystick = @import("joystick.zig");

const port = 45041;
const heartbeat_lease_ms = 15_000;
pub const update_interval_ms = 50;
pub const Packet = [8]u8;
pub const neutral: Packet = .{ 31, 128, 128, 0, 128, 0, 128, 0 };

const Peer = struct {
    destination: c.struct_sockaddr_in,
    expires: i64,
};

fd: c_int,
peers: [32]?Peer = @splat(null),

const Network = @This();

pub fn open(address: c.in_addr) !Network {
    const fd = c.socket(c.AF_INET, c.SOCK_DGRAM | c.SOCK_NONBLOCK | c.SOCK_CLOEXEC, 0);
    if (fd < 0) return error.OpenSocket;
    errdefer _ = c.close(fd);

    var endpoint: c.struct_sockaddr_in = std.mem.zeroes(c.struct_sockaddr_in);
    endpoint.sin_family = c.AF_INET;
    endpoint.sin_addr = address;
    endpoint.sin_port = std.mem.nativeToBig(u16, port);
    if (c.bind(fd, .{ .__sockaddr_in__ = &endpoint }, @sizeOf(c.struct_sockaddr_in)) != 0) return error.BindSocket;
    return .{ .fd = fd };
}

fn putByte(value: f64) u8 {
    return @intFromFloat(std.math.clamp(@round(value), 0, 255));
}

fn heading(value: f64) u8 {
    return putByte(@mod(value * 180, 360) * (255.0 / 360.0));
}

pub fn encode(input: Joystick) Packet {
    const axes = input.axes;
    var buttons: u8 = 0;
    for (input.buttons, 0..) |pressed, index| {
        if (pressed) buttons |= @as(u8, 1) << @as(u3, @intCast(index));
    }
    return .{
        31,
        putByte(axes[0] * 128 + 128),
        putByte(axes[1] * 128 + 128),
        heading(axes[4]),
        putByte(axes[5] * 128 + 128),
        heading(axes[2]),
        putByte(axes[3] * 128 + 128),
        buttons,
    };
}

fn send(self: Network, data: []const u8, endpoint: *const c.struct_sockaddr_in) !void {
    const written = c.sendto(self.fd, data.ptr, data.len, 0, .{ .__sockaddr_in__ = endpoint }, @sizeOf(c.struct_sockaddr_in));
    if (written == data.len) return;
    // UDP is best effort. Temporary buffer pressure or a departed route can
    // drop this datagram; the next state or discovery request tries again.
    const code = std.posix.errno(written);
    if (code == .AGAIN or code == .INTR or code == .NOBUFS or code == .NETUNREACH or code == .HOSTUNREACH) return;
    return error.SendSocket;
}

pub fn expire(self: *Network, now: i64) void {
    for (&self.peers) |*slot| {
        if (slot.*) |peer| {
            if (now >= peer.expires) slot.* = null;
        }
    }
}

pub fn publish(self: Network, packet: Packet) !void {
    for (self.peers) |slot| {
        if (slot) |peer| try self.send(&packet, &peer.destination);
    }
}

pub fn receive(self: *Network, now: i64, packet: Packet) !void {
    // With a three-byte buffer oversized datagrams always fail the length test.
    for (0..32) |_| {
        var message: [3]u8 = undefined;
        var sender: c.struct_sockaddr_in = undefined;
        var sender_size: c.socklen_t = @sizeOf(c.struct_sockaddr_in);
        const length = c.recvfrom(self.fd, &message, message.len, 0, .{ .__sockaddr_in__ = &sender }, &sender_size);
        if (length < 0) {
            const code = std.posix.errno(length);
            if (code == .AGAIN or code == .INTR) return;
            return error.ReceiveSocket;
        }
        if (length != 2 or message[0] != 1) continue;
        if (message[1] != 2 and message[1] != 21) continue;

        const sender_port = std.mem.bigToNative(u16, sender.sin_port);
        if (sender_port == 0 or sender_port == 65535) continue;
        sender.sin_port = std.mem.nativeToBig(u16, sender_port + 1);
        try self.accept(sender, message[1], now, packet);
    }
}

fn accept(self: *Network, destination: c.struct_sockaddr_in, request: u8, now: i64, packet: Packet) !void {
    var available: ?*?Peer = null;
    var existing: ?*?Peer = null;
    for (&self.peers) |*slot| {
        if (slot.*) |peer| {
            if (peer.destination.sin_addr.s_addr == destination.sin_addr.s_addr and
                peer.destination.sin_port == destination.sin_port)
            {
                existing = slot;
                break;
            }
        } else if (available == null) available = slot;
    }

    if (request == 21) {
        if (existing) |slot| {
            slot.*.?.expires = now + heartbeat_lease_ms;
            try self.send(&packet, &destination);
        }
        return;
    }
    const slot = existing orelse available orelse return;
    slot.* = .{ .destination = destination, .expires = now + heartbeat_lease_ms };
    try self.send(&.{ 1, 2 }, &destination);
    try self.send(&packet, &destination);
}
