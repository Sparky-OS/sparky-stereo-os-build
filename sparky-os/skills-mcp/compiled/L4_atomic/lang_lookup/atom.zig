//! L4 atom: which language file serves a locale. Whole locale, then the bare language, then English.
const std = @import("std");

/// `available` are language ids such as "fr", "pt_BR", "zh_TW"; `locale` is `LANG` such as "fr_CA.UTF-8".
pub fn pick(available: []const []const u8, locale: []const u8) []const u8 {
    _ = available;
    _ = locale;
    return "";
}
