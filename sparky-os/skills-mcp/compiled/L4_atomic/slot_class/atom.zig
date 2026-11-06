//! L4 atom: what a command slot may hold. Zig's standard library has no regular expressions, and a fixed set of
//! classes cannot be made to run for ever on crafted input, so a slot names a class instead of a pattern.
//! Classes: "word" ([A-Za-z0-9._-]+, 1 to 64), "int" (optional minus, 1 to 9 digits), "enum:a,b,c" (one of the listed words).
const std = @import("std");

pub fn matches(class: []const u8, value: []const u8) bool {
    if (std.mem.eql(u8, class, "word")) {
        if (value.len == 0 or value.len > 64) return false;
        for (value) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '_' or ch == '-')) return false;
        return true;
    }
    if (std.mem.eql(u8, class, "int")) {
        var v = value;
        if (v.len > 0 and v[0] == '-') v = v[1..];
        if (v.len == 0 or v.len > 9) return false;
        for (v) |ch| if (!std.ascii.isDigit(ch)) return false;
        return true;
    }
    if (std.mem.startsWith(u8, class, "enum:")) {
        var it = std.mem.splitScalar(u8, class["enum:".len..], ',');
        while (it.next()) |w| if (w.len > 0 and std.mem.eql(u8, w, value)) return true;
        return false;
    }
    return false;
}

pub fn validClass(class: []const u8) bool {
    return std.mem.eql(u8, class, "word") or std.mem.eql(u8, class, "int") or (std.mem.startsWith(u8, class, "enum:") and class.len > 5);
}
