//! Memory required-languages: the whole locale, then the bare language, then English; Chinese keeps its territory.
const std = @import("std");
const lang_lookup = @import("lang_lookup");

const nine = [_][]const u8{ "en", "pl", "pt_BR", "fr", "de", "ja", "ko", "zh_CN", "zh_TW" };

test "whole locale first" {
    try std.testing.expectEqualStrings("pt_BR", lang_lookup.pick(&nine, "pt_BR.UTF-8", "en"));
    try std.testing.expectEqualStrings("zh_TW", lang_lookup.pick(&nine, "zh_TW.UTF-8", "en"));
}

test "the bare language serves every territory of it" {
    try std.testing.expectEqualStrings("fr", lang_lookup.pick(&nine, "fr_CA.UTF-8", "en"));
    try std.testing.expectEqualStrings("de", lang_lookup.pick(&nine, "de_AT", "en"));
}

test "Chinese keeps its territory: a missing zh_TW is English, never zh_CN" {
    const no_tw = [_][]const u8{ "en", "zh_CN", "fr" };
    try std.testing.expectEqualStrings("en", lang_lookup.pick(&no_tw, "zh_TW.UTF-8", "en"));
}

test "anything unknown or unset is English" {
    try std.testing.expectEqualStrings("en", lang_lookup.pick(&nine, "C", "en"));
    try std.testing.expectEqualStrings("en", lang_lookup.pick(&nine, "", "en"));
    try std.testing.expectEqualStrings("en", lang_lookup.pick(&nine, "sw_KE.UTF-8", "en"));
}
