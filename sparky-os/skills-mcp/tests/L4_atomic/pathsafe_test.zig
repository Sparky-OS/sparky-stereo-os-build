//! MCP resources page: servers must validate resource URIs and sanitize file paths against directory traversal.
//! Agent Skills specification: a name is lowercase letters, digits and single hyphens, at most 64 characters.
const std = @import("std");
const pathsafe = @import("pathsafe");

test "valid skill names" {
    try std.testing.expect(pathsafe.validName("audio"));
    try std.testing.expect(pathsafe.validName("3d-to-vr"));
    try std.testing.expect(pathsafe.validName("a" ** 64));
}

test "invalid skill names are refused" {
    for ([_][]const u8{ "", "Audio", "-a", "a-", "a--b", "a_b", "a b", "a/b", "../a", "a" ** 65 }) |n| {
        try std.testing.expect(!pathsafe.validName(n));
    }
}

test "ordinary relative paths pass unchanged" {
    try std.testing.expectEqualStrings("SKILL.md", try pathsafe.check("SKILL.md"));
    try std.testing.expectEqualStrings("references/a.md", try pathsafe.check("references/a.md"));
}

test "each traversal form is refused (negative controls, one by one)" {
    for ([_][]const u8{ "../x", "a/../../x", "/etc/passwd", "a\x00b", "%2e%2e/x", "%2E%2e/x", "a\\..\\x", "a//b/..", ".." }) |p| {
        try std.testing.expectError(error.Refused, pathsafe.check(p));
    }
}

test "a resolved path outside the root is refused, inside is accepted" {
    try pathsafe.checkResolved("/usr/share/agent-skills/user/a", "/usr/share/agent-skills/user/a/SKILL.md");
    try std.testing.expectError(error.Refused, pathsafe.checkResolved("/usr/share/agent-skills/user/a", "/etc/passwd"));
    try std.testing.expectError(error.Refused, pathsafe.checkResolved("/usr/share/agent-skills/user/a", "/usr/share/agent-skills/user/ab/SKILL.md"));
}
