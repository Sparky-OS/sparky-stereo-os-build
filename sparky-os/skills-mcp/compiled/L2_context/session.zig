//! L2 context: one run's context: who is asking (home, data directories, language), which packages are installed,
//! what the person saved (the command policy and the assistants registered), and which skill kinds exist.
const std = @import("std");
const fsio = @import("fsio");
const dpkg_status = @import("dpkg_status");
const eligibility = @import("eligibility");
const statefile = @import("statefile");
const command_gate = @import("command_gate");
const ai_detect = @import("ai_detect");
const lang_lookup = @import("lang_lookup");
const kinds = @import("kinds_skill_kind");

pub const Kind = struct { folder: []const u8, translations_required: bool, commands_allowed: bool, holds_reference_tree: bool };

pub const Session = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    home: []const u8,
    xdg_home: []const u8,
    xdg_dirs: []const u8,
    locale: []const u8,
    state_path: []const u8,
    kinds: []const Kind,
    installed: eligibility.Installed,

    pub fn load(arena: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map) !Session {
        const home = env.get("HOME") orelse "";
        const xdg_home = env.get("XDG_DATA_HOME") orelse if (home.len > 0) try std.fmt.allocPrint(arena, "{s}/.local/share", .{home}) else "";
        const cfg = env.get("XDG_CONFIG_HOME") orelse if (home.len > 0) try std.fmt.allocPrint(arena, "{s}/.config", .{home}) else "";
        var ks: std.ArrayList(Kind) = .empty;
        inline for (kinds.all) |k| try ks.append(arena, .{ .folder = k.folder, .translations_required = k.translations_required, .commands_allowed = k.commands_allowed, .holds_reference_tree = k.holds_reference_tree });
        return .{
            .arena = arena,
            .io = io,
            .env = env,
            .home = home,
            .xdg_home = xdg_home,
            .xdg_dirs = env.get("XDG_DATA_DIRS") orelse "",
            .locale = env.get("LC_ALL") orelse env.get("LC_MESSAGES") orelse env.get("LANG") orelse "",
            .state_path = if (cfg.len > 0) try std.fmt.allocPrint(arena, "{s}/sparky-stereo-skills/state", .{cfg}) else "",
            .kinds = ks.items,
            .installed = try readInstalled(arena, io, env),
        };
    }

    pub fn kindFolders(self: Session, arena: std.mem.Allocator) ![]const []const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        for (self.kinds) |k| try out.append(arena, k.folder);
        return out.items;
    }

    pub fn kindNamed(self: Session, folder: []const u8) ?Kind {
        for (self.kinds) |k| if (std.mem.eql(u8, k.folder, folder)) return k;
        return null;
    }

    fn stateText(self: Session) []const u8 {
        if (self.state_path.len == 0) return "";
        return fsio.readFile(self.arena, self.io, self.state_path, 64 * 1024) catch "";
    }

    pub fn commandsPolicy(self: Session) command_gate.Policy {
        const v = statefile.get(self.stateText(), "COMMANDS") orelse return .auto;
        return command_gate.parsePolicy(v) orelse .auto;
    }

    pub fn setCommandsPolicy(self: Session, p: command_gate.Policy) !void {
        if (self.state_path.len == 0) return error.NoHome;
        const next = try statefile.set(self.arena, self.stateText(), "COMMANDS", @tagName(p));
        try fsio.writeReplace(self.io, self.state_path, next);
    }

    /// Space separated ids of the assistants the person registered the server with.
    pub fn registered(self: Session) []const u8 {
        return statefile.get(self.stateText(), "MCP") orelse "";
    }

    pub fn setRegistered(self: Session, ids: []const u8) !void {
        if (self.state_path.len == 0) return error.NoHome;
        const next = try statefile.set(self.arena, self.stateText(), "MCP", if (ids.len == 0) null else ids);
        try fsio.writeReplace(self.io, self.state_path, next);
    }

    /// Which of `assistants` the person already uses: a program on PATH or a configuration folder in the home.
    pub fn assistantsFound(self: Session, assistants: []const ai_detect.Assistant) ![]const []const u8 {
        var on_path: std.ArrayList([]const u8) = .empty;
        var in_home: std.ArrayList([]const u8) = .empty;
        const path = self.env.get("PATH") orelse "";
        for (assistants) |a| {
            for (a.programs) |prog| {
                var dirs = std.mem.splitScalar(u8, path, ':');
                while (dirs.next()) |d| {
                    if (d.len == 0) continue;
                    if (fsio.exists(self.io, try std.fmt.allocPrint(self.arena, "{s}/{s}", .{ d, prog }))) {
                        try on_path.append(self.arena, prog);
                        break;
                    }
                }
            }
            for (a.home_dirs) |h| if (self.home.len > 0 and fsio.exists(self.io, try std.fmt.allocPrint(self.arena, "{s}/{s}", .{ self.home, h }))) try in_home.append(self.arena, h);
        }
        return ai_detect.found(self.arena, assistants, .{ .on_path = on_path.items, .in_home = in_home.items });
    }

    pub fn language(self: Session, available: []const []const u8, fallback: []const u8) []const u8 {
        return lang_lookup.pick(available, self.locale, fallback);
    }
};

/// `SPARKY_STEREO_PACKAGES` (space separated) replaces dpkg's status file, as the helper has always allowed for tests.
/// An unreadable status file is an error: skills are never all served because the check could not be made.
fn readInstalled(arena: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map) !eligibility.Installed {
    if (env.get("SPARKY_STEREO_PACKAGES")) |p| {
        var out: std.ArrayList([]const u8) = .empty;
        var it = std.mem.tokenizeAny(u8, p, " \t\n");
        while (it.next()) |n| try out.append(arena, n);
        return .{ .names = out.items };
    }
    const text = fsio.readFile(arena, io, "/var/lib/dpkg/status", 256 << 20) catch return error.DpkgStatusUnreadable;
    return .{ .names = try dpkg_status.installed(arena, text) };
}
