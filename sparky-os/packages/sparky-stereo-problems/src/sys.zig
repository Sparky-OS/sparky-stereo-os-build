// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The C library and libsystemd calls the engine makes, declared with the types glibc and libsystemd use on Linux.
// The engine talks to the system only through these: files and folders, processes, time, the journal (sd-journal) and
// systemd's unit state (sd-bus), so the same code serves the command and the C library.

pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_RDWR: c_int = 2;
pub const O_CREAT: c_int = 0o100;
pub const O_EXCL: c_int = 0o200;
pub const O_TRUNC: c_int = 0o1000;
pub const O_NOFOLLOW: c_int = 0o400000;
pub const O_CLOEXEC: c_int = 0o2000000;
pub const LOCK_EX: c_int = 2;
pub const LOCK_UN: c_int = 8;
pub const ENOENT: c_int = 2;
pub const EINTR: c_int = 4;
pub const EEXIST: c_int = 17;
pub const SD_JOURNAL_LOCAL_ONLY: c_int = 1;
pub const SD_JOURNAL_SYSTEM: c_int = 4;

pub const iovec = extern struct {
    base: ?*const anyopaque,
    len: usize,
};

// struct dirent of glibc on 64-bit Linux (the same layout as dirent64)
pub const Dirent = extern struct {
    ino: u64,
    off: i64,
    reclen: u16,
    type: u8,
    name: [256]u8,
};

pub const Tm = extern struct {
    sec: c_int,
    min: c_int,
    hour: c_int,
    mday: c_int,
    mon: c_int,
    year: c_int,
    wday: c_int,
    yday: c_int,
    isdst: c_int,
    gmtoff: c_long,
    zone: ?[*:0]const u8,
};

pub const Passwd = extern struct {
    name: [*:0]u8,
    passwd: ?[*:0]u8,
    uid: u32,
    gid: u32,
    gecos: ?[*:0]u8,
    dir: [*:0]u8,
    shell: ?[*:0]u8,
};

pub const BusError = extern struct {
    name: ?[*:0]const u8 = null,
    message: ?[*:0]const u8 = null,
    need_free: c_int = 0,
};

pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
pub extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
pub extern "c" fn close(fd: c_int) c_int;
pub extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
pub extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
pub extern "c" fn fsync(fd: c_int) c_int;
pub extern "c" fn fchmod(fd: c_int, mode: c_uint) c_int;
pub extern "c" fn flock(fd: c_int, op: c_int) c_int;
pub extern "c" fn rename(from: [*:0]const u8, to: [*:0]const u8) c_int;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
pub extern "c" fn opendir(path: [*:0]const u8) ?*anyopaque;
pub extern "c" fn readdir(dir: *anyopaque) ?*Dirent;
pub extern "c" fn closedir(dir: *anyopaque) c_int;
pub extern "c" fn __errno_location() *c_int;
pub extern "c" fn strerror(errnum: c_int) [*:0]const u8;
pub extern "c" fn geteuid() u32;
pub extern "c" fn getuid() u32;
pub extern "c" fn getpid() c_int;
pub extern "c" fn getpwuid(uid: u32) ?*Passwd;
pub extern "c" fn fork() c_int;
pub extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
pub extern "c" fn waitpid(pid: c_int, status: *c_int, options: c_int) c_int;
pub extern "c" fn pipe(fds: *[2]c_int) c_int;
pub extern "c" fn dup2(old: c_int, new: c_int) c_int;
pub extern "c" fn _exit(status: c_int) noreturn;
pub extern "c" fn time(t: ?*i64) i64;
pub const Timespec = extern struct { sec: i64, nsec: i64 };
pub extern "c" fn clock_gettime(clock: c_int, ts: *Timespec) c_int;
pub extern "c" fn gmtime_r(t: *const i64, out: *Tm) ?*Tm;
pub extern "c" fn getrandom(buf: [*]u8, n: usize, flags: c_uint) isize;
pub extern "c" fn malloc(n: usize) ?*anyopaque;
pub extern "c" fn free(p: ?*anyopaque) void;

pub extern "c" fn sd_journal_sendv(iov: [*]const iovec, n: c_int) c_int;
pub extern "c" fn sd_journal_open(ret: *?*anyopaque, flags: c_int) c_int;
pub extern "c" fn sd_journal_close(j: ?*anyopaque) void;
pub extern "c" fn sd_journal_add_match(j: *anyopaque, data: [*]const u8, size: usize) c_int;
pub extern "c" fn sd_journal_add_disjunction(j: *anyopaque) c_int;
pub extern "c" fn sd_journal_seek_tail(j: *anyopaque) c_int;
pub extern "c" fn sd_journal_previous(j: *anyopaque) c_int;
pub extern "c" fn sd_journal_get_data(j: *anyopaque, field: [*:0]const u8, data: *?[*]const u8, len: *usize) c_int;
pub extern "c" fn sd_bus_open_system(ret: *?*anyopaque) c_int;
pub extern "c" fn sd_bus_flush_close_unref(bus: ?*anyopaque) ?*anyopaque;
pub extern "c" fn sd_bus_path_encode(prefix: [*:0]const u8, external_id: [*:0]const u8, ret_path: *?[*:0]u8) c_int;
pub extern "c" fn sd_bus_get_property_string(bus: *anyopaque, destination: [*:0]const u8, path: [*:0]const u8, interface: [*:0]const u8, member: [*:0]const u8, ret_error: *BusError, ret: *?[*:0]u8) c_int;
pub extern "c" fn sd_bus_error_free(e: *BusError) void;

pub fn errno() c_int {
    return __errno_location().*;
}
