//! L4 atom: which language file serves a locale. Whole locale, then the bare language, then English.
const std = @import("std");

/// `available` are language ids such as "fr", "pt_BR", "zh_TW"; `locale` is `LANG` such as "fr_CA.UTF-8".
/// `fallback` is the language the program is written in (the registry marks it), never a literal here.
pub fn pick(available: []const []const u8, locale: []const u8, fallback: []const u8) []const u8 {
    var end = locale.len;
    for (locale, 0..) |ch, i| if (ch == '.' or ch == '@') {
        end = i;
        break;
    };
    const whole = locale[0..end];
    for (available) |a| if (std.mem.eql(u8, a, whole)) return a;
    const bare_end = std.mem.indexOfScalar(u8, whole, '_') orelse whole.len;
    const bare = whole[0..bare_end];
    if (bare.len > 0 and !std.mem.eql(u8, bare, "zh")) {
        for (available) |a| if (std.mem.eql(u8, a, bare)) return a;
    }
    return fallback;
}
