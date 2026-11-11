//! sparky-stereo-skills: the program. `serve` is the MCP door (stdio only), every other verb is the command line door.
const std = @import("std");
const engine = @import("engine");
const mcp_server = @import("mcp_server");
const cli_verbs = @import("cli_verbs");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const verb = args.next() orelse {
        return cli_verbs.run(init, &.{});
    };
    if (std.mem.eql(u8, verb, "serve")) {
        if (std.os.linux.geteuid() == 0) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.stderr().writer(init.io, &buf);
            try w.interface.writeAll("The skills server is started by an assistant as the person, never as root.\n");
            try w.interface.flush();
            std.process.exit(2);
        }
        return mcp_server.serve(init, cli_verbs.assistantList());
    }
    var rest: std.ArrayList([]const u8) = .empty;
    try rest.append(init.arena.allocator(), verb);
    while (args.next()) |a| try rest.append(init.arena.allocator(), a);
    return cli_verbs.run(init, rest.items);
}
