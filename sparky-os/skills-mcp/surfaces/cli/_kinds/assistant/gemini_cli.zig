//! Assistant: gemini. Registered only on the person's yes, through the assistant's own command where it has one.
pub const id = "gemini_cli";
pub const programs = [_][]const u8{"gemini"};
pub const home_dirs = [_][]const u8{".gemini"};
/// From each assistant's own documentation (read 2026-11-06); the absolute path survives a launcher with another PATH.
pub const register_argv: []const []const u8 = &[_][]const u8{ "gemini", "mcp", "add", "-s", "user", "sparky-stereo-skills", "/usr/bin/sparky-stereo-skills", "serve" };
/// Codex and OpenCode: the removal command is the documented guess; `mcp status` verifies the result by asking the assistant.
pub const unregister_argv: []const []const u8 = &[_][]const u8{ "gemini", "mcp", "remove", "-s", "user", "sparky-stereo-skills" };
pub const unregister_note: []const u8 = "";
/// Asks the assistant whether the server is registered with it.
pub const list_argv: []const []const u8 = &[_][]const u8{ "gemini", "mcp", "list" };
