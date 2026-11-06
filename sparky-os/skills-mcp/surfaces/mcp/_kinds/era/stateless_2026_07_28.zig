//! Protocol era: MCP 2026-07-28, stateless (server/discover, every request carries its version in `params._meta`).
pub const id = "stateless";
pub const revision = "2026-07-28";

pub fn recognises(method: []const u8, meta_has_protocol_version: bool, initialized: bool) bool {
    _ = method;
    _ = initialized;
    return meta_has_protocol_version;
}
