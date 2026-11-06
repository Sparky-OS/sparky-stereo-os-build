//! L5 operation: the commands a user skill lists in `commands.json`, as data. The skill's Markdown may show a
//! command, but only a command in this file can ever run (an assistant runs only commands a skill lists).
//! Shape: [{"id","argv":["prog","{slot}"],"slots":{"slot":"word|int|enum:a,b"},"expect":{"exit":0,"stdout_contains":"text"},"run":"assistant|person"}]
const std = @import("std");
const fsio = @import("fsio");
const slot_class = @import("slot_class");
const command_spec = @import("command_spec");
const skill_record = @import("skill_record");

pub const Slot = command_spec.Slot;
pub const Command = command_spec.Command;

const Raw = struct {
    id: []const u8,
    argv: []const []const u8,
    slots: std.json.ArrayHashMap([]const u8) = .{},
    expect: struct { exit: ?u8 = null, stdout_contains: []const u8 = "" } = .{},
    run: []const u8 = "person",
};

pub const Error = error{BadCommands} || std.mem.Allocator.Error;

/// `json` of a skill's commands.json. A malformed file is `error.BadCommands`, never an empty list.
pub fn parse(arena: std.mem.Allocator, json: []const u8) Error![]const Command {
    const raws = std.json.parseFromSliceLeaky([]const Raw, arena, json, .{}) catch return error.BadCommands;
    var out: std.ArrayList(Command) = .empty;
    for (raws) |r| {
        if (r.id.len == 0 or r.argv.len == 0) return error.BadCommands;
        var slots: std.ArrayList(Slot) = .empty;
        var it = r.slots.map.iterator();
        while (it.next()) |kv| {
            if (!slot_class.validClass(kv.value_ptr.*)) return error.BadCommands;
            try slots.append(arena, .{ .name = kv.key_ptr.*, .class = kv.value_ptr.* });
        }
        for (r.argv) |tok| {
            // A slot is a whole argument, written {name}; a brace inside a longer argument is refused.
            if (std.mem.indexOfAny(u8, tok, "{}") != null) {
                if (tok.len < 3 or tok[0] != '{' or tok[tok.len - 1] != '}') return error.BadCommands;
                var declared = false;
                for (slots.items) |s| if (std.mem.eql(u8, s.name, tok[1 .. tok.len - 1])) {
                    declared = true;
                };
                if (!declared) return error.BadCommands;
            }
        }
        const marked: command_spec.Marked = if (std.mem.eql(u8, r.run, "assistant")) .assistant else if (std.mem.eql(u8, r.run, "person")) .person else return error.BadCommands;
        try out.append(arena, .{ .id = r.id, .argv = r.argv, .slots = slots.items, .expect_exit = r.expect.exit, .expect_contains = r.expect.stdout_contains, .marked = marked });
    }
    return out.items;
}

/// The commands of `rec`, or an empty list when it has no commands.json.
pub fn load(arena: std.mem.Allocator, io: std.Io, rec: skill_record.Rec) Error![]const Command {
    const path = try std.fmt.allocPrint(arena, "{s}/commands.json", .{rec.dir});
    const text = fsio.readFile(arena, io, path, 256 * 1024) catch |e| switch (e) {
        error.FileNotFound => return &.{},
        else => return if (e == error.OutOfMemory) e else error.BadCommands,
    };
    return parse(arena, text);
}
