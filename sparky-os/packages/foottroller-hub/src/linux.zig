// SPDX-License-Identifier: GPL-3.0-or-later
pub const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("arpa/inet.h");
    @cInclude("dirent.h");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("linux/joystick.h");
    @cInclude("linux/uinput.h");
    @cInclude("poll.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("sys/signalfd.h");
    @cInclude("sys/stat.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});
