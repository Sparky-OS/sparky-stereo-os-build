//! L4 atom: a sliding window of calls (MCP tools page: servers must rate limit tool invocations).
const std = @import("std");

pub const Window = struct {
    stamps: [64]i64 = [_]i64{std.math.minInt(i64)} ** 64,
    next: usize = 0,
    limit: usize = 50,
    window_ms: i64 = 10_000,

    /// True when a call at `now_ms` is allowed; the call is counted only when allowed.
    pub fn allow(self: *Window, now_ms: i64) bool {
        var recent: usize = 0;
        for (self.stamps) |s| if (s != std.math.minInt(i64) and now_ms - s < self.window_ms and now_ms >= s) {
            recent += 1;
        };
        if (recent >= self.limit) return false;
        self.stamps[self.next] = now_ms;
        self.next = (self.next + 1) % self.stamps.len;
        return true;
    }
};
