//! Protocol era: the legacy MCP revisions (initialize first). Most assistants speak this today.
const std = @import("std");

pub const id = "legacy";
pub const revision = "2025-11-25";

/// A request belongs to this era when the process has been initialized with `initialize`
/// and the request carries no protocol version in `params._meta`.
pub fn recognises(method: []const u8, meta_has_protocol_version: bool, initialized: bool) bool {
    return !meta_has_protocol_version and (initialized or std.mem.eql(u8, method, "initialize"));
}
