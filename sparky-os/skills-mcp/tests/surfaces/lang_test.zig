//! The nine required languages: every string the server adds ships in the nine languages, each file with the
//! same keys as English and the same placeholders.
const std = @import("std");
const langs = @import("kinds_lang");

const required = [_][]const u8{ "de", "en", "fr", "ja", "ko", "pl", "pt_BR", "zh_CN", "zh_TW" };

test "the nine required languages are present, no more and no fewer files than the set" {
    try std.testing.expectEqual(required.len, langs.names.len);
    for (required, langs.names) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "every language has the English keys and keeps the {s} placeholder where English has it" {
    const a = std.testing.allocator;
    const en = try std.json.parseFromSlice(std.json.Value, a, @import("kinds_lang").all[1].strings_json, .{});
    defer en.deinit();
    inline for (langs.all) |l| {
        const doc = try std.json.parseFromSlice(std.json.Value, a, l.strings_json, .{});
        defer doc.deinit();
        var it = en.value.object.iterator();
        while (it.next()) |kv| {
            const got = doc.value.object.get(kv.key_ptr.*) orelse return error.MissingKey;
            const want_ph = std.mem.indexOf(u8, kv.value_ptr.string, "{s}") != null;
            const got_ph = std.mem.indexOf(u8, got.string, "{s}") != null;
            try std.testing.expectEqual(want_ph, got_ph);
            try std.testing.expect(got.string.len > 0);
        }
        try std.testing.expectEqual(en.value.object.count(), doc.value.object.count());
    }
}
