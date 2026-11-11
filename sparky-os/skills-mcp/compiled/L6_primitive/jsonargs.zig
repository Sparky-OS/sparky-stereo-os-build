//! L6 primitive: reading the arguments of a request, which are outside input and are checked here, never assumed.
const std = @import("std");

pub const Error = error{InvalidArgument};

pub fn object(v: std.json.Value) Error!std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        .null => std.json.ObjectMap.empty,
        else => error.InvalidArgument,
    };
}

pub fn string(o: std.json.ObjectMap, key: []const u8) Error!?[]const u8 {
    const v = o.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        .null => null,
        else => error.InvalidArgument,
    };
}

pub fn requiredString(o: std.json.ObjectMap, key: []const u8) Error![]const u8 {
    return (try string(o, key)) orelse error.InvalidArgument;
}

pub fn int(o: std.json.ObjectMap, key: []const u8) Error!?i64 {
    const v = o.get(key) orelse return null;
    return switch (v) {
        .integer => |i| i,
        .null => null,
        else => error.InvalidArgument,
    };
}

pub fn boolean(o: std.json.ObjectMap, key: []const u8) Error!?bool {
    const v = o.get(key) orelse return null;
    return switch (v) {
        .bool => |b| b,
        .null => null,
        else => error.InvalidArgument,
    };
}

pub fn strings(arena: std.mem.Allocator, o: std.json.ObjectMap, key: []const u8) (Error || std.mem.Allocator.Error)![]const []const u8 {
    const v = o.get(key) orelse return &.{};
    switch (v) {
        .null => return &.{},
        .array => |a| {
            var out: std.ArrayList([]const u8) = .empty;
            for (a.items) |it| switch (it) {
                .string => |s| try out.append(arena, s),
                else => return error.InvalidArgument,
            };
            return out.items;
        },
        else => return error.InvalidArgument,
    }
}
