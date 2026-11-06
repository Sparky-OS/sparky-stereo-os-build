//! L4 atom: is a skill installed, by its `requires-packages` field. `a | b` means any one of them.
const std = @import("std");

pub const Installed = struct {
    names: []const []const u8,

    pub fn has(self: Installed, name: []const u8) bool {
        for (self.names) |n| if (std.mem.eql(u8, n, name)) return true;
        return false;
    }
};

pub fn allowed(field: []const u8, installed: Installed) bool {
    const trimmed = std.mem.trim(u8, field, " \t");
    if (trimmed.len == 0) return true;
    var it = std.mem.splitScalar(u8, trimmed, '|');
    while (it.next()) |alt| {
        const name = std.mem.trim(u8, alt, " \t");
        if (name.len == 0) continue;
        if (installed.has(name)) return true;
    }
    return false;
}
