//! MCP versioning: a request whose params._meta carries io.modelcontextprotocol/protocolVersion is served
//! statelessly (2026-07-28); a process that was initialized with `initialize` is served as the legacy era.
//! Both eras are variants dropped into surfaces/mcp/_kinds/era/.
const std = @import("std");
const eras = @import("kinds_era");

test "the registry holds exactly the two eras the plan names" {
    try std.testing.expectEqual(@as(usize, 2), eras.names.len);
    try std.testing.expectEqualStrings("legacy_2025_11_25", eras.names[0]);
    try std.testing.expectEqualStrings("stateless_2026_07_28", eras.names[1]);
}

test "revisions are the ones the specification names" {
    const legacy = eras.all[0];
    const stateless = eras.all[1];
    try std.testing.expectEqualStrings("2025-11-25", legacy.revision);
    try std.testing.expectEqualStrings("2026-07-28", stateless.revision);
}

test "a modern request carries its version in _meta, a legacy one follows initialize" {
    const legacy = eras.all[0];
    const stateless = eras.all[1];
    try std.testing.expect(stateless.recognises("tools/list", true, false));
    try std.testing.expect(!stateless.recognises("tools/list", false, true));
    try std.testing.expect(legacy.recognises("tools/list", false, true));
    try std.testing.expect(!legacy.recognises("tools/list", true, false));
    try std.testing.expect(legacy.recognises("initialize", false, false));
    try std.testing.expect(stateless.recognises("server/discover", true, false));
}
