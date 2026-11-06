//! L6 primitive: the names of the installed packages in dpkg's status file (Debian Policy 5.6.12, Status field).
//! A package counts when its Status ends in "installed" (not "config-files", "half-installed" or "not-installed").
const std = @import("std");

/// Names, in file order, without duplicates removed (a Multi-Arch: same package appears once per architecture).
pub fn installed(gpa: std.mem.Allocator, status_text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var pkg: []const u8 = "";
    var ok = false;
    var lines = std.mem.splitScalar(u8, status_text, '\n');
    while (true) {
        const line = lines.next();
        if (line == null or line.?.len == 0) {
            if (ok and pkg.len > 0) try out.append(gpa, try gpa.dupe(u8, pkg));
            pkg = "";
            ok = false;
            if (line == null) break;
            continue;
        }
        const l = line.?;
        if (l[0] == ' ' or l[0] == '\t') continue;
        if (std.mem.startsWith(u8, l, "Package:")) {
            pkg = std.mem.trim(u8, l["Package:".len..], " \t");
        } else if (std.mem.startsWith(u8, l, "Status:")) {
            const v = std.mem.trim(u8, l["Status:".len..], " \t");
            ok = std.mem.endsWith(u8, v, " installed") and !std.mem.startsWith(u8, v, "deinstall ok half") and !std.mem.endsWith(u8, v, "not-installed");
        }
    }
    return out.toOwnedSlice(gpa);
}
