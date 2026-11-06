//! Assistant: gemini. Registered only on the person's yes, through the assistant's own command where it has one.
pub const id = "gemini_cli";
pub const programs = [_][]const u8{"gemini"};
pub const home_dirs = [_][]const u8{".gemini"};
/// Empty until milestone 2b fills it from the table in the plan (section 4).
pub const register_argv: []const []const u8 = &.{};
pub const unregister_argv: []const []const u8 = &.{};
