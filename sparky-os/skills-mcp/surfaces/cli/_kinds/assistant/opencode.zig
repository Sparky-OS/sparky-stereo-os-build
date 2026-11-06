//! Assistant: opencode. Registered only on the person's yes, through the assistant's own command where it has one.
pub const id = "opencode";
pub const programs = [_][]const u8{"opencode"};
pub const home_dirs = [_][]const u8{".config/opencode"};
/// From each assistant's own documentation (read 2026-11-06); the absolute path survives a launcher with another PATH.
pub const register_argv: []const []const u8 = &[_][]const u8{ "opencode", "mcp", "add", "sparky-stereo-skills", "--global", "--", "/usr/bin/sparky-stereo-skills", "serve" };
/// The assistant's documentation names no removal command (read 2026-11-06), so none is invented: the person is told what to delete.
pub const unregister_argv: []const []const u8 = &.{};
pub const unregister_note: []const u8 = "delete the sparky-stereo-skills entry under mcp in your opencode.jsonc";
