//! Registration goes through each assistant's own command (plan section 4, documentation read 2026-11-06).
//! The command written is the absolute /usr/bin/sparky-stereo-skills, so a launcher's PATH cannot break it.
const std = @import("std");
const assistants = @import("kinds_assistant");

fn expectArgv(want: []const []const u8, got: []const []const u8) !void {
    try std.testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try std.testing.expectEqualStrings(w, g);
}

test "the registry has the five assistants that have a command of their own" {
    try std.testing.expectEqual(@as(usize, 5), assistants.names.len);
}

test "Claude Code" {
    inline for (assistants.all) |a| if (comptime std.mem.eql(u8, a.id, "claude_code")) {
        try expectArgv(&.{ "claude", "mcp", "add", "--scope", "user", "sparky-stereo-skills", "--", "/usr/bin/sparky-stereo-skills", "serve" }, a.register_argv);
        try expectArgv(&.{ "claude", "mcp", "remove", "sparky-stereo-skills", "--scope", "user" }, a.unregister_argv);
    };
}

test "Codex and Gemini CLI" {
    inline for (assistants.all) |a| {
        if (comptime std.mem.eql(u8, a.id, "codex"))
            try expectArgv(&.{ "codex", "mcp", "add", "sparky-stereo-skills", "--", "/usr/bin/sparky-stereo-skills", "serve" }, a.register_argv);
        if (comptime std.mem.eql(u8, a.id, "gemini_cli")) {
            try expectArgv(&.{ "gemini", "mcp", "add", "-s", "user", "sparky-stereo-skills", "/usr/bin/sparky-stereo-skills", "serve" }, a.register_argv);
            try expectArgv(&.{ "gemini", "mcp", "remove", "-s", "user", "sparky-stereo-skills" }, a.unregister_argv);
        }
    }
}

test "OpenCode and Cline" {
    inline for (assistants.all) |a| {
        if (comptime std.mem.eql(u8, a.id, "opencode"))
            try expectArgv(&.{ "opencode", "mcp", "add", "sparky-stereo-skills", "--global", "--", "/usr/bin/sparky-stereo-skills", "serve" }, a.register_argv);
        if (comptime std.mem.eql(u8, a.id, "cline")) {
            try expectArgv(&.{ "cline", "mcp", "add", "sparky-stereo-skills", "--yes", "--", "/usr/bin/sparky-stereo-skills", "serve" }, a.register_argv);
            try expectArgv(&.{ "cline", "mcp", "remove", "sparky-stereo-skills" }, a.unregister_argv);
        }
    }
}
