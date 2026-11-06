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
    _ = field;
    _ = installed;
    return false;
}
