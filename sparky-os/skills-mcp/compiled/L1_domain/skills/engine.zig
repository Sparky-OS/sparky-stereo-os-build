//! L1 domain: the skills engine, the one API every door calls. The command line, the MCP server and the dialog
//! are three doors onto this; none of them holds skill logic.
//! A failure is a value with a plain sentence in `message` (what failed, why, what to do); nothing is retried on another path.
const std = @import("std");
const session_mod = @import("session");
const catalogue = @import("catalogue");
const op_find = @import("op_find");
const op_list = @import("op_list");
const op_sections = @import("op_sections");
const op_context = @import("op_context");
const op_read = @import("op_read");
const op_manifest = @import("op_manifest");
const op_commands = @import("op_commands");
const op_run = @import("op_run");
const command_gate = @import("command_gate");
const ai_detect = @import("ai_detect");
const skill_record = @import("skill_record");
const skill_uri = @import("skill_uri");
const sections = @import("sections");
const manifest = @import("manifest");
const fsio = @import("fsio");

pub const Session = session_mod.Session;
pub const Rec = skill_record.Rec;
pub const Origin = skill_record.Origin;
pub const FindRow = op_find.Row;
pub const Policy = command_gate.Policy;
pub const Via = command_gate.Via;
pub const Heading = sections.Heading;
pub const ManifestEntry = manifest.Entry;
pub const Command = op_commands.Command;
pub const RunValue = op_run.Value;
pub const Outcome = op_run.Outcome;
pub const Assistant = ai_detect.Assistant;

pub const Failure = error.Failed;

pub const Engine = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    session: Session,
    /// Set whenever a call returns `error.Failed`.
    message: []const u8 = "",
    /// Sentences about things skipped while reading the trees (an unknown kind folder, a broken front matter).
    problems: std.ArrayList([]const u8) = .empty,
    recs: []const Rec = &.{},
    ref_root: ?[]const u8 = null,

    pub fn init(arena: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map) !Engine {
        var e: Engine = .{ .arena = arena, .io = io, .session = try Session.load(arena, io, env) };
        try e.refresh();
        return e;
    }

    /// A live scan; no cache. The scan costs a few milliseconds and is always current.
    pub fn refresh(self: *Engine) !void {
        const found = try catalogue.discover(self.arena, self.io, self.session.xdg_home, self.session.xdg_dirs, try self.session.kindFolders(self.arena));
        for (found.problems) |p| try self.problems.append(self.arena, p);
        self.recs = try catalogue.scan(self.arena, self.io, found.trees, self.session.installed, &self.problems);
        self.ref_root = self.session.env.get("SPARKY_STEREO_REF");
        if (self.ref_root == null) for (found.trees) |t| {
            const holds = if (self.session.kindNamed(t.kind)) |k| k.holds_reference_tree else false;
            if (holds and std.mem.endsWith(u8, t.path, "/skills")) {
                const parent = t.path[0 .. t.path.len - "/skills".len];
                if (fsio.exists(self.io, std.fmt.allocPrint(self.arena, "{s}/AGENTS.md", .{parent}) catch continue)) {
                    self.ref_root = parent;
                    break;
                }
            }
        };
    }

    /// An engine over one explicit tree of skills, for tests and `--root`: every skill counts as installed.
    pub fn initTree(arena: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, kind: []const u8, path: []const u8, ref_root: ?[]const u8) !Engine {
        var e: Engine = .{ .arena = arena, .io = io, .session = try Session.load(arena, io, env) };
        const trees = [_]catalogue.Tree{.{ .origin = .system, .kind = kind, .path = path }};
        e.recs = try catalogue.scan(arena, io, &trees, e.session.installed, &e.problems);
        e.ref_root = ref_root;
        return e;
    }

    fn fail(self: *Engine, comptime fmt: []const u8, args: anytype) error{Failed} {
        self.message = std.fmt.allocPrint(self.arena, fmt, args) catch "out of memory";
        return error.Failed;
    }

    pub fn find(self: *Engine, query: []const u8, limit: usize, all: bool) ![]const FindRow {
        if (limit == 0 or limit > 10) return self.fail("The limit must be 1 to 10.", .{});
        return op_find.run(self.arena, self.recs, query, limit, all) catch |e| switch (e) {
            error.EmptyQuery => self.fail("Describe the task or symptom in a few words.", .{}),
            else => e,
        };
    }

    pub fn list(self: *Engine, kind: ?[]const u8, all: bool) ![]const Rec {
        return op_list.run(self.arena, self.recs, kind, all);
    }

    pub fn uri(self: *Engine, r: Rec, file: []const u8) ![]u8 {
        return skill_uri.format(self.arena, @tagName(r.origin), r.kind, r.name, file);
    }

    /// The one skill called `name` that is installed; a name in two origins is refused with both addresses.
    pub fn resolve(self: *Engine, name: []const u8, origin: ?Origin) !Rec {
        var hit: ?Rec = null;
        var count: usize = 0;
        var ineligible = false;
        for (self.recs) |r| {
            if (!std.mem.eql(u8, r.name, name)) continue;
            if (origin) |o| if (o != r.origin) continue;
            if (!r.eligible) {
                ineligible = true;
                continue;
            }
            hit = r;
            count += 1;
        }
        if (count == 1) return hit.?;
        if (count == 0) {
            if (ineligible) return self.fail("The skill '{s}' needs a package that is not installed ({s}), so it is not served. Install it, or ask for all skills.", .{ name, self.requiresOf(name) });
            return self.fail("No skill is called '{s}'. Use find or list to see the installed skills.", .{name});
        }
        var msg: std.ArrayList(u8) = .empty;
        try msg.print(self.arena, "More than one skill is called '{s}'; say which one you mean:", .{name});
        for (self.recs) |r| if (r.eligible and std.mem.eql(u8, r.name, name)) try msg.print(self.arena, " {s}", .{try self.uri(r, "SKILL.md")});
        self.message = msg.items;
        return error.Failed;
    }

    fn requiresOf(self: *Engine, name: []const u8) []const u8 {
        for (self.recs) |r| if (std.mem.eql(u8, r.name, name)) return r.requires_packages;
        return "";
    }

    pub fn sectionsOf(self: *Engine, name: []const u8) ![]const Heading {
        return op_sections.run(self.arena, self.io, try self.resolve(name, null));
    }

    pub const ContextRequest = struct {
        names: []const []const u8 = &.{},
        /// Each "skill-name:Exact heading".
        sections: []const []const u8 = &.{},
        references: []const []const u8 = &.{},
        max_chars: usize = 48000,
    };

    pub fn context(self: *Engine, req: ContextRequest) ![]const u8 {
        var picks: std.ArrayList(op_context.Pick) = .empty;
        for (req.names) |n| try picks.append(self.arena, .{ .rec = try self.resolve(n, null) });
        for (req.sections) |s| {
            const colon = std.mem.indexOfScalar(u8, s, ':') orelse return self.fail("A section is written skill-name:Exact heading.", .{});
            if (colon + 1 >= s.len) return self.fail("A section is written skill-name:Exact heading.", .{});
            try picks.append(self.arena, .{ .rec = try self.resolve(s[0..colon], null), .title = s[colon + 1 ..] });
        }
        const res = try op_context.run(self.arena, self.io, .{ .ref_root = self.ref_root, .picks = picks.items, .references = req.references, .max_chars = req.max_chars });
        return switch (res) {
            .text => |t| t,
            .failed => |m| blk: {
                self.message = m;
                break :blk error.Failed;
            },
        };
    }

    pub fn read(self: *Engine, name: []const u8, origin: ?Origin, file: []const u8) ![]u8 {
        const r = try self.resolve(name, origin);
        return op_read.run(self.arena, self.io, r, file) catch |e| switch (e) {
            error.Refused => self.fail("That path is not inside the skill's own folder, so it was refused.", .{}),
            error.TooLarge => self.fail("That file is over 256 KiB. Use context with a section instead.", .{}),
            error.NotText => self.fail("That file is not valid UTF-8 text, so it was not served.", .{}),
            error.NotFound => self.fail("The skill '{s}' has no file '{s}'.", .{ name, file }),
            else => |o| o,
        };
    }

    pub fn manifestOf(self: *Engine, name: []const u8, origin: ?Origin) ![]const ManifestEntry {
        const r = try self.resolve(name, origin);
        return op_manifest.run(self.arena, self.io, r) catch |e| switch (e) {
            error.TooManyFiles => self.fail("The skill '{s}' has more than 512 files, so it is listed but not served.", .{name}),
            error.TooLarge => self.fail("The skill '{s}' is over 16 MiB, so it is listed but not served.", .{name}),
            else => e,
        };
    }

    pub fn commands(self: *Engine, name: []const u8) ![]const Command {
        const r = try self.resolve(name, null);
        const k = self.session.kindNamed(r.kind);
        if (k == null or !k.?.commands_allowed) return self.fail("Skills of kind '{s}' list no commands.", .{r.kind});
        return op_commands.load(self.arena, self.io, r) catch self.fail("The commands.json of '{s}' is malformed, so no command of it is offered.", .{name});
    }

    /// The decision the gate makes for one command of one skill, and the command itself.
    pub fn gate(self: *Engine, name: []const u8, id: []const u8, via: Via, assistants: []const Assistant) !struct { cmd: ?Command, decision: command_gate.Decision, ai_found: []const []const u8 } {
        const cmds = try self.commands(name);
        var cmd: ?Command = null;
        for (cmds) |c| if (std.mem.eql(u8, c.id, id)) {
            cmd = c;
        };
        const found = try self.session.assistantsFound(assistants);
        const decision = command_gate.decide(self.session.commandsPolicy(), found.len > 0, cmd != null, if (cmd) |c| switch (c.marked) {
            .assistant => command_gate.Marked.assistant,
            .person => command_gate.Marked.person,
        } else .person, via);
        return .{ .cmd = cmd, .decision = decision, .ai_found = found };
    }

    /// Runs a command the caller has already had approved (by the assistant or by the person, as `gate` said).
    pub fn runApproved(self: *Engine, name: []const u8, id: []const u8, values: []const RunValue) !Outcome {
        const cmds = try self.commands(name);
        return op_run.run(self.arena, self.io, cmds, id, values, self.session.env) catch |e| switch (e) {
            error.NotListed => self.fail("That command is not listed by the skill, so it was not run.", .{}),
            error.BadSlot => self.fail("A value does not fit what the command accepts, so it was not run.", .{}),
            error.MissingSlot => self.fail("The command needs a value that was not given, so it was not run.", .{}),
            error.RunningAsRoot => self.fail("Commands from skills are never run as root.", .{}),
            else => e,
        };
    }
};
