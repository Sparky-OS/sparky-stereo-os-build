//! The MCP door: JSON-RPC over stdio, one message per line, nothing but messages on stdout, a log line per request on stderr.
//! Two protocol eras are served from one process: a request that carries io.modelcontextprotocol/protocolVersion in
//! params._meta is stateless (2026-07-28); after `initialize` the process answers as the legacy era (2025-11-25).
//! Which era a request belongs to is asked of the era variants dropped into _kinds/era; the tools likewise from _kinds/tool.
//! The Skills extension (io.modelcontextprotocol/skills, SEP-2640): skills/list, skills/get and skill:// resources.
const std = @import("std");
const engine = @import("engine");
const eras = @import("kinds_era");
const tools = @import("kinds_tool");

pub const server_name = "sparky-stereo-skills";
pub const server_version = "0.1.0";
pub const meta_key = "io.modelcontextprotocol/protocolVersion";
const skills_ext = "io.modelcontextprotocol/skills";
const instructions = "Call skills_find first with the task in plain words, then skills_context with the skill it names. Nothing here runs a command unless the person's command policy allows it.";

pub const Server = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    assistants: []const engine.Assistant,
    initialized: bool = false,
    window: engine.RateWindow = .{},

    /// The reply for one input line, or null for a notification. `arena` lives for this request.
    pub fn handleLine(self: *Server, arena: std.mem.Allocator, line: []const u8, log: *Log) !?[]const u8 {
        const t0 = std.Io.Timestamp.now(self.io, .real).toMilliseconds();
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, line, .{}) catch {
            log.set("-", "", t0, "-32700");
            return try errorReply(arena, "null", -32700, "Parse error: the line is not valid JSON.");
        };
        const obj = switch (parsed) {
            .object => |o| o,
            else => {
                log.set("-", "", t0, "-32600");
                return try errorReply(arena, "null", -32600, "Invalid request: one JSON object per line (batches are not supported).");
            },
        };
        const id_text: ?[]const u8 = if (obj.get("id")) |i| try std.json.Stringify.valueAlloc(arena, i, .{}) else null;
        const method = switch (obj.get("method") orelse .null) {
            .string => |m| m,
            else => {
                log.set("-", "", t0, "-32600");
                return try errorReply(arena, id_text orelse "null", -32600, "Invalid request: no method.");
            },
        };
        const params: std.json.Value = obj.get("params") orelse .null;
        const params_obj: std.json.ObjectMap = switch (params) {
            .object => |o| o,
            else => std.json.ObjectMap.empty,
        };
        const has_meta = if (params_obj.get("_meta")) |m| switch (m) {
            .object => |mo| mo.contains(meta_key),
            else => false,
        } else false;
        if (id_text == null) {
            if (std.mem.eql(u8, method, "notifications/initialized")) self.initialized = true;
            log.set(method, "", t0, "ok");
            return null;
        }
        const id = id_text.?;
        // The era: asked of the variants.
        var modern = false;
        inline for (eras.all) |era| {
            if (comptime std.mem.eql(u8, era.id, "stateless")) {
                if (era.recognises(method, has_meta, self.initialized)) modern = true;
            }
        }
        if (!modern and !self.initialized and !std.mem.eql(u8, method, "initialize") and !std.mem.eql(u8, method, "ping")) {
            log.set(method, "", t0, "-32602");
            return try errorReply(arena, id, -32602, "Missing params._meta (io.modelcontextprotocol/protocolVersion), and no initialize was sent.");
        }
        if (std.mem.eql(u8, method, "server/discover") and !has_meta) {
            log.set(method, "", t0, "-32602");
            return try errorReply(arena, id, -32602, "server/discover needs params._meta with io.modelcontextprotocol/protocolVersion.");
        }

        var eng = engine.Engine.init(arena, self.io, self.env) catch |e| {
            log.set(method, "", t0, "-32603");
            return try errorReply(arena, id, -32603, try std.fmt.allocPrint(arena, "The skills could not be read: {s}. Nothing is served.", .{@errorName(e)}));
        };
        eng.assistants = self.assistants;

        var subject: []const u8 = "";
        const result = self.dispatch(arena, &eng, method, params_obj, modern, &subject) catch |e| {
            const code: i32 = switch (e) {
                error.UnknownMethod => -32601,
                error.InvalidArgument, error.NotFound => -32602,
                error.RateLimited => -32000,
                else => -32603,
            };
            var code_buf: [8]u8 = undefined;
            log.set(method, subject, t0, std.fmt.bufPrint(&code_buf, "{d}", .{code}) catch "err");
            const text: []const u8 = switch (e) {
                error.UnknownMethod => "Method not found.",
                error.InvalidArgument => "Invalid params.",
                error.NotFound => if (eng.message.len > 0) eng.message else "Unknown tool or resource.",
                error.RateLimited => "Rate limit: more than 50 calls in 10 seconds. Wait a moment and try again.",
                else => "Internal error.",
            };
            return try errorReply(arena, id, code, text);
        };
        log.set(method, subject, t0, "ok");
        return try std.fmt.allocPrint(arena, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}", .{ id, result });
    }

    const DispatchError = error{ UnknownMethod, InvalidArgument, NotFound, RateLimited, Internal } || std.mem.Allocator.Error;

    fn cacheable(modern: bool) []const u8 {
        return if (modern) ",\"resultType\":\"complete\",\"ttlMs\":5000,\"cacheScope\":\"private\"" else "";
    }

    fn dispatch(self: *Server, arena: std.mem.Allocator, eng: *engine.Engine, method: []const u8, p: std.json.ObjectMap, modern: bool, subject: *[]const u8) DispatchError![]const u8 {
        const rt: []const u8 = if (modern) "\"resultType\":\"complete\"," else "";
        if (std.mem.eql(u8, method, "ping")) return std.fmt.allocPrint(arena, "{{{s}}}", .{if (modern) "\"resultType\":\"complete\"" else ""});
        if (std.mem.eql(u8, method, "initialize")) {
            self.initialized = true;
            var rev: []const u8 = "";
            inline for (eras.all) |era| if (comptime std.mem.eql(u8, era.id, "legacy")) {
                rev = era.revision;
            };
            return std.fmt.allocPrint(arena, "{{\"protocolVersion\":\"{s}\",\"capabilities\":{s},\"serverInfo\":{{\"name\":\"{s}\",\"version\":\"{s}\"}},\"instructions\":{s}}}", .{ rev, capabilities, server_name, server_version, try std.json.Stringify.valueAlloc(arena, instructions, .{}) });
        }
        if (std.mem.eql(u8, method, "server/discover")) {
            var versions: std.ArrayList(u8) = .empty;
            inline for (eras.all) |era| if (comptime std.mem.eql(u8, era.id, "stateless")) {
                try versions.print(arena, "\"{s}\"", .{era.revision});
            };
            // the shape the 2026-07-28 schema gives DiscoverResult: supportedVersions, capabilities, ttlMs and cacheScope
            // are required, the server's name goes in _meta under io.modelcontextprotocol/serverInfo
            return std.fmt.allocPrint(arena, "{{{s}\"supportedVersions\":[{s}],\"capabilities\":{s},\"instructions\":{s},\"ttlMs\":5000,\"cacheScope\":\"private\",\"_meta\":{{\"io.modelcontextprotocol/serverInfo\":{{\"name\":\"{s}\",\"version\":\"{s}\"}}}}}}", .{ rt, versions.items, capabilities, try std.json.Stringify.valueAlloc(arena, instructions, .{}), server_name, server_version });
        }
        if (std.mem.eql(u8, method, "tools/list")) {
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(arena, "{\"tools\":[");
            inline for (tools.all, 0..) |t, i| {
                if (i > 0) try out.append(arena, ',');
                try out.print(arena, "{{\"name\":\"{s}\",\"description\":{s},\"inputSchema\":{s},\"annotations\":{{\"readOnlyHint\":{s},\"openWorldHint\":false}}}}", .{ t.name, try std.json.Stringify.valueAlloc(arena, t.description, .{}), t.input_schema, if (t.read_only) "true" else "false" });
            }
            try out.print(arena, "]{s}}}", .{cacheable(modern)});
            return out.items;
        }
        if (std.mem.eql(u8, method, "tools/call")) {
            if (!self.window.allow(std.Io.Timestamp.now(self.io, .real).toMilliseconds())) return error.RateLimited;
            const name = switch (p.get("name") orelse .null) {
                .string => |s| s,
                else => return error.InvalidArgument,
            };
            subject.* = name;
            const args: std.json.Value = p.get("arguments") orelse .null;
            inline for (tools.all) |t| {
                if (std.mem.eql(u8, t.name, name)) {
                    var is_error = false;
                    const text: []const u8 = t.call(eng, args) catch |e| switch (e) {
                        error.Failed => blk: {
                            is_error = true;
                            break :blk eng.message;
                        },
                        error.InvalidArgument => return error.InvalidArgument,
                        else => blk: {
                            if (e == error.OutOfMemory) return e;
                            is_error = true;
                            break :blk try std.fmt.allocPrint(arena, "The call failed: {s}.", .{@errorName(e)});
                        },
                    };
                    return std.fmt.allocPrint(arena, "{{{s}\"content\":[{{\"type\":\"text\",\"text\":{s}}}],\"isError\":{s}}}", .{ rt, try std.json.Stringify.valueAlloc(arena, text, .{}), if (is_error) "true" else "false" });
                }
            }
            return error.InvalidArgument;
        }
        if (std.mem.eql(u8, method, "resources/templates/list")) {
            return std.fmt.allocPrint(arena, "{{\"resourceTemplates\":[{{\"uriTemplate\":\"skill://{{origin}}/{{kind}}/{{name}}/{{+file}}\",\"name\":\"A file of a skill\",\"mimeType\":\"text/markdown\"}}]{s}}}", .{cacheable(modern)});
        }
        if (std.mem.eql(u8, method, "resources/list")) {
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(arena, "{\"resources\":[");
            var first = true;
            for (try eng.list(null, false)) |r| {
                const m = eng.manifestOf(r.name, r.origin) catch continue;
                for (m) |entry| {
                    if (!first) try out.append(arena, ',');
                    first = false;
                    try out.print(arena, "{{\"uri\":{s},\"name\":{s},\"mimeType\":\"text/markdown\"}}", .{ try std.json.Stringify.valueAlloc(arena, entry.uri, .{}), try std.json.Stringify.valueAlloc(arena, std.fs.path.basename(entry.uri), .{}) });
                }
            }
            try out.print(arena, "]{s}}}", .{cacheable(modern)});
            return out.items;
        }
        if (std.mem.eql(u8, method, "resources/read")) {
            const uri = switch (p.get("uri") orelse .null) {
                .string => |s| s,
                else => return error.InvalidArgument,
            };
            subject.* = uri;
            const parsed = engine.parseUri(uri) catch return error.InvalidArgument;
            const origin = std.meta.stringToEnum(engine.Origin, parsed.origin) orelse return error.InvalidArgument;
            const text = eng.read(parsed.name, origin, parsed.file) catch |e| switch (e) {
                error.Failed => return error.NotFound,
                else => return error.Internal,
            };
            return std.fmt.allocPrint(arena, "{{\"contents\":[{{\"uri\":{s},\"mimeType\":\"text/markdown\",\"text\":{s}}}]{s}}}", .{ try std.json.Stringify.valueAlloc(arena, uri, .{}), try std.json.Stringify.valueAlloc(arena, text, .{}), cacheable(modern) });
        }
        if (std.mem.eql(u8, method, "skills/list")) {
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(arena, "{\"skills\":[");
            var first = true;
            for (try eng.list(null, false)) |r| {
                const entry = skillEntry(arena, eng, r) catch |e| switch (e) {
                    else => {
                        if (e == error.OutOfMemory) return e;
                        continue; // a broken skill is not served; skills/get names the reason
                    },
                };
                if (!first) try out.append(arena, ',');
                first = false;
                try out.appendSlice(arena, entry);
            }
            try out.print(arena, "]{s}}}", .{cacheable(modern)});
            return out.items;
        }
        if (std.mem.eql(u8, method, "skills/get")) {
            const uri = switch (p.get("uri") orelse .null) {
                .string => |s| s,
                else => return error.InvalidArgument,
            };
            subject.* = uri;
            const parsed = engine.parseUri(uri) catch return error.InvalidArgument;
            if (!std.mem.eql(u8, parsed.file, "SKILL.md")) return error.InvalidArgument;
            const origin = std.meta.stringToEnum(engine.Origin, parsed.origin) orelse return error.InvalidArgument;
            const r = eng.resolve(parsed.name, origin) catch return error.NotFound;
            const entry = skillEntry(arena, eng, r) catch |e| switch (e) {
                else => return if (e == error.OutOfMemory) e else error.NotFound,
            };
            return std.fmt.allocPrint(arena, "{{\"skill\":{s}{s}}}", .{ entry, cacheable(modern) });
        }
        return error.UnknownMethod;
    }

    fn skillEntry(arena: std.mem.Allocator, eng: *engine.Engine, r: engine.Rec) ![]const u8 {
        const text = try eng.skillText(r);
        const fm = try engine.frontmatterJson(arena, text);
        const m = try eng.manifestOf(r.name, r.origin);
        var out: std.ArrayList(u8) = .empty;
        try out.print(arena, "{{\"uri\":{s},\"frontmatter\":{s},\"resources\":[", .{ try std.json.Stringify.valueAlloc(arena, try eng.uri(r, "SKILL.md"), .{}), fm });
        for (m, 0..) |e, i| {
            if (i > 0) try out.append(arena, ',');
            try out.print(arena, "{{\"uri\":{s},\"digest\":\"{s}\",\"size\":{d}}}", .{ try std.json.Stringify.valueAlloc(arena, e.uri, .{}), &e.digest, e.size });
        }
        try out.appendSlice(arena, "]}");
        return out.items;
    }
};

const capabilities = "{\"tools\":{\"listChanged\":false},\"resources\":{\"listChanged\":false},\"extensions\":{\"" ++ skills_ext ++ "\":{}}}";

fn errorReply(arena: std.mem.Allocator, id: []const u8, code: i32, message: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":{s}}}}}", .{ id, code, try std.json.Stringify.valueAlloc(arena, message, .{}) });
}

/// One stderr line per request: UTC time, method, tool or address, milliseconds, ok or the error code.
/// Never the query text and never file contents.
pub const Log = struct {
    method: []const u8 = "",
    subject: []const u8 = "",
    started: i64 = 0,
    outcome_buf: [16]u8 = undefined,
    outcome_len: usize = 0,

    /// `outcome` is copied: it may live in a buffer of the caller's that is gone by the time the line is written.
    pub fn set(self: *Log, method: []const u8, subject: []const u8, started: i64, outcome: []const u8) void {
        self.method = method;
        self.subject = subject;
        self.started = started;
        self.outcome_len = @min(outcome.len, self.outcome_buf.len);
        @memcpy(self.outcome_buf[0..self.outcome_len], outcome[0..self.outcome_len]);
    }

    pub fn outcomeText(self: *const Log) []const u8 {
        return self.outcome_buf[0..self.outcome_len];
    }
};

/// The loop. Returns when stdin closes.
pub fn serve(init: std.process.Init, assistants: []const engine.Assistant) !void {
    const io = init.io;
    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buf);
    var out_buf: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);
    var err_buf: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &err_buf);
    var server: Server = .{ .gpa = init.gpa, .io = io, .env = init.environ_map, .assistants = assistants };
    while (true) {
        const line = stdin.interface.takeDelimiter('\n') catch |e| switch (e) {
            error.StreamTooLong => {
                try stdout.interface.writeAll("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"The line is longer than 64 KiB.\"}}\n");
                try stdout.interface.flush();
                continue;
            },
            else => return e,
        } orelse break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        var arena_state = std.heap.ArenaAllocator.init(init.gpa);
        defer arena_state.deinit();
        var log: Log = .{};
        const reply = server.handleLine(arena_state.allocator(), trimmed, &log) catch |e| blk: {
            log.set("-", "", std.Io.Timestamp.now(io, .real).toMilliseconds(), "-32603");
            break :blk try errorReply(arena_state.allocator(), "null", -32603, try std.fmt.allocPrint(arena_state.allocator(), "Internal error: {s}.", .{@errorName(e)}));
        };
        if (reply) |r| {
            try stdout.interface.writeAll(r);
            try stdout.interface.writeAll("\n");
            try stdout.interface.flush();
        }
        const now = std.Io.Timestamp.now(io, .real).toMilliseconds();
        const secs: u64 = @intCast(@divTrunc(now, 1000));
        const day = std.time.epoch.EpochSeconds{ .secs = secs };
        const ds = day.getDaySeconds();
        const yd = day.getEpochDay().calculateYearDay();
        const md = yd.calculateMonthDay();
        try stderr.interface.print("{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z {s} {s} {d}ms {s}\n", .{ yd.year, md.month.numeric(), md.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute(), log.method, log.subject, now - log.started, log.outcomeText() });
        try stderr.interface.flush();
    }
}
