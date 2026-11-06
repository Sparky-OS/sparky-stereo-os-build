//! L4 atom: the shape of one command a user skill lists. Data only; reading it is `op_commands`, running it is `op_run`.
const std = @import("std");

pub const Marked = enum { assistant, person };

pub const Slot = struct { name: []const u8, class: []const u8 };

pub const Command = struct {
    id: []const u8,
    /// The program and its arguments; an argument written {name} is a slot, always a whole argument.
    argv: []const []const u8,
    slots: []const Slot,
    expect_exit: ?u8,
    expect_contains: []const u8,
    marked: Marked,
};
