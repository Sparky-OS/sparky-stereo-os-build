//! L4 atom: the offline, deterministic ranking of skills for a task or symptom, equal to the Python `find`
//! (tools/skills-context.py at the commit recorded in data/golden/SOURCE): terms are stemmed words, weight(t) =
//! ln(1 + (N - n + 0.5) / (n + 0.5)), fields name 3.0, task table 2.0, description 1.0.
const std = @import("std");

pub const Skill = struct {
    name: []const u8,
    description: []const u8,
    /// The skills index's task-table text for this skill; empty when none.
    task_rows: []const u8,
};

pub const Row = struct { name: []const u8, score: f64 };

const stopwords = [_][]const u8{
    "a",     "about", "after", "all",   "also",  "an",    "and",   "any",   "are",   "as",   "at",    "be",   "been", "before", "both", "but",
    "by",    "can",   "could", "did",   "do",    "does",  "each",  "every", "for",   "from", "had",    "has",  "have", "how",    "i",    "if",
    "in",    "into",  "is",    "it",    "its",   "just",  "may",   "me",    "might", "more", "most",   "must", "my",   "no",     "not",  "of",
    "on",    "one",   "only",  "or",    "other", "our",   "out",   "over",  "same",  "should", "so",   "some", "such", "than",   "that", "the",
    "their", "them",  "then",  "there", "these", "they",  "this",  "those", "three", "to",   "two",    "under", "up",  "us",     "very", "was",
    "we",    "were",  "what",  "when",  "where", "which", "who",   "why",   "will",  "with", "without", "would", "you",  "your",
};

fn isStop(w: []const u8) bool {
    for (stopwords) |s| if (std.mem.eql(u8, s, w)) return true;
    return false;
}

/// The Python `stem`, on an already lowercase ASCII word. Returns a slice of `buf`.
fn stem(word: []const u8, buf: []u8) []const u8 {
    var len = word.len;
    @memcpy(buf[0..len], word);
    var w = buf[0..len];
    if (w.len > 4 and std.mem.endsWith(u8, w, "ies")) {
        len = w.len - 3 + 1;
        buf[len - 1] = 'y';
        w = buf[0..len];
    } else if (w.len > 3 and std.mem.endsWith(u8, w, "s") and !std.mem.endsWith(u8, w, "ss")) {
        w = w[0 .. w.len - 1];
    }
    inline for (.{ "ing", "ed" }) |suffix| {
        if (w.len > suffix.len + 2 and std.mem.endsWith(u8, w, suffix)) {
            w = w[0 .. w.len - suffix.len];
            if (w.len > 2 and w[w.len - 1] == w[w.len - 2] and std.mem.indexOfScalar(u8, "lsz", w[w.len - 1]) == null) w = w[0 .. w.len - 1];
            break;
        }
    }
    if (w.len > 4 and w[w.len - 1] == 'e') w = w[0 .. w.len - 1];
    return w;
}

/// The set of stemmed, non-stop words of `text` (a-z and 0-9 runs of the lowercased text).
fn terms(arena: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        while (i < text.len and !std.ascii.isAlphanumeric(text[i])) i += 1;
        const start = i;
        while (i < text.len and std.ascii.isAlphanumeric(text[i])) i += 1;
        if (i == start) break;
        const raw = text[start..i];
        const lower = try arena.alloc(u8, raw.len);
        for (raw, 0..) |ch, k| lower[k] = std.ascii.toLower(ch);
        if (isStop(lower)) continue;
        const buf = try arena.alloc(u8, lower.len + 1);
        const s = stem(lower, buf);
        var dup = false;
        for (out.items) |o| if (std.mem.eql(u8, o, s)) {
            dup = true;
        };
        if (!dup) try out.append(arena, s);
    }
    return out.toOwnedSlice(arena);
}

fn has(set: []const []const u8, t: []const u8) bool {
    for (set) |s| if (std.mem.eql(u8, s, t)) return true;
    return false;
}

/// Rows with a score above zero, best first, ties by name, at most `limit`.
pub fn rank(arena: std.mem.Allocator, skills: []const Skill, query: []const u8, limit: usize) ![]const Row {
    const wanted = try terms(arena, query);
    if (wanted.len == 0) return error.EmptyQuery;
    const Fields = struct { name: []const []const u8, readme: []const []const u8, desc: []const []const u8 };
    const fields = try arena.alloc(Fields, skills.len);
    for (skills, 0..) |s, i| {
        const spaced = try arena.dupe(u8, s.name);
        for (spaced) |*ch| if (ch.* == '-') {
            ch.* = ' ';
        };
        fields[i] = .{ .name = try terms(arena, spaced), .readme = try terms(arena, s.task_rows), .desc = try terms(arena, s.description) };
    }
    const n_total: f64 = @floatFromInt(skills.len);
    const weight = try arena.alloc(f64, wanted.len);
    for (wanted, 0..) |t, k| {
        var n: f64 = 0;
        for (fields) |f| if (has(f.name, t) or has(f.readme, t) or has(f.desc, t)) {
            n += 1;
        };
        weight[k] = @log(1.0 + (n_total - n + 0.5) / (n + 0.5));
    }
    var scored: std.ArrayList(Row) = .empty;
    for (skills, 0..) |s, i| {
        var score: f64 = 0;
        for (wanted, 0..) |t, k| {
            if (has(fields[i].name, t)) score += weight[k] * 3.0;
            if (has(fields[i].readme, t)) score += weight[k] * 2.0;
            if (has(fields[i].desc, t)) score += weight[k] * 1.0;
        }
        if (score > 0) try scored.append(arena, .{ .name = s.name, .score = @round(score * 1e6) / 1e6 });
    }
    std.mem.sort(Row, scored.items, {}, struct {
        fn lt(_: void, a: Row, b: Row) bool {
            if (a.score != b.score) return a.score > b.score;
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    return scored.items[0..@min(limit, scored.items.len)];
}
