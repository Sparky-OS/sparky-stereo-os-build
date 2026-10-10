#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest-only console isolation probe; the main session runs it in the VM."""

import argparse
import array
import configparser
import fcntl
import glob
import hashlib
import io
import json
import os
import pwd
import re
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

TIOCLINUX = 0x541C
KDGETMODE = 0x4B3B
VT_GETSTATE = 0x5603
VT_ACTIVATE = 0x5606
VT_WAITACTIVE = 0x5607
POINTS = {15: "dim", 135: "planned-show", 165: "screen-off", 240: "laptop-sleep-boundary"}
FORBIDDEN = {"setterm", "xset", "xscreensaver", "xscreensaver-systemd", "gnome-screensaver",
             "cinnamon-screensaver", "mate-screensaver", "xautolock"}


class Mismatch(Exception):
    pass


class DpmsReader:
    """Read KWin's DPMS protocol; never create a surface or request a mode."""

    def __init__(self, path):
        self.connection = socket.socket(socket.AF_UNIX)
        self.connection.settimeout(5)
        self.connection.connect(path)
        self.buffer = b""
        self.next_id = 3
        self.globals = []
        self.states = {}

    def send(self, target, opcode, payload):
        self.connection.sendall(struct.pack("=II", target, ((8 + len(payload)) << 16) | opcode) + payload)

    def allocate(self):
        self.next_id += 1
        return self.next_id

    @staticmethod
    def string(value):
        data = value.encode() + b"\0"
        return struct.pack("=I", len(data)) + data + b"\0" * (-len(data) % 4)

    def roundtrip(self):
        callback = self.allocate()
        self.send(1, 0, struct.pack("=I", callback))
        while True:
            while len(self.buffer) < 8:
                data = self.connection.recv(65536)
                if not data:
                    raise RuntimeError("Wayland connection closed")
                self.buffer += data
            target, word = struct.unpack_from("=II", self.buffer)
            size, opcode = word >> 16, word & 0xFFFF
            if size < 8:
                raise RuntimeError("Invalid Wayland message size")
            while len(self.buffer) < size:
                data = self.connection.recv(65536)
                if not data:
                    raise RuntimeError("Incomplete Wayland event")
                self.buffer += data
            payload, self.buffer = self.buffer[8:size], self.buffer[size:]
            if target == 1 and opcode == 0:
                raise RuntimeError("Wayland protocol error")
            if target == callback:
                return
            if target == 2 and opcode == 0:
                name, length = struct.unpack_from("=II", payload)
                interface = payload[8:8 + length - 1].decode()
                version = struct.unpack_from("=I", payload, 8 + ((length + 3) & ~3))[0]
                self.globals.append((name, interface, version))
            if target in self.states and opcode in (0, 1):
                self.states[target]["supported" if opcode == 0 else "mode"] = struct.unpack("=I", payload)[0]

    def bind(self, name, interface):
        identifier = self.allocate()
        self.send(2, 0, struct.pack("=I", name) + self.string(interface) + struct.pack("=II", 1, identifier))
        return identifier

    def read(self):
        try:
            self.send(1, 1, struct.pack("=I", 2))
            self.roundtrip()
            managers = [name for name, interface, version in self.globals
                        if interface == "org_kde_kwin_dpms_manager"]
            if len(managers) != 1:
                raise RuntimeError("KWin DPMS manager is unavailable")
            manager = self.bind(managers[0], "org_kde_kwin_dpms_manager")
            for name, interface, version in self.globals:
                if interface == "wl_output":
                    output = self.bind(name, interface)
                    identifier = self.allocate()
                    self.states[identifier] = {"global": name}
                    self.send(manager, 0, struct.pack("=II", identifier, output))
            self.roundtrip()
            states = list(self.states.values())
            if not states or any("mode" not in state or "supported" not in state for state in states):
                raise RuntimeError("Incomplete DPMS state")
            return states
        finally:
            self.connection.close()


def command(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


def active_vt(fd):
    state = bytearray(6)
    fcntl.ioctl(fd, VT_GETSTATE, state)
    return struct.unpack("=HHH", state)[0]


def activate(fd, vt):
    fcntl.ioctl(fd, VT_ACTIVATE, vt)
    fcntl.ioctl(fd, VT_WAITACTIVE, vt)


def blanked_vt(fd):
    return fcntl.ioctl(fd, TIOCLINUX, bytearray([15]), True)


def power_state():
    files = glob.glob("/sys/class/graphics/fb*/blank")
    files += glob.glob("/sys/class/graphics/fb*/device/power/control")
    files += glob.glob("/sys/class/graphics/fb*/device/power/runtime_status")
    for directory in glob.glob("/sys/class/drm/card*-*"):
        status = Path(directory) / "status"
        if status.exists() and status.read_text().strip() == "connected" and (Path(directory) / "dpms").exists():
            files.append(directory + "/dpms")
    return {path: Path(path).read_text().strip() for path in sorted(files)}


def snapshot(fds):
    consoles = {}
    for number, fd in fds.items():
        mode = array.array("i", [0])
        fcntl.ioctl(fd, KDGETMODE, mode, True)
        screen = Path(f"/dev/vcsa{number}").read_bytes()
        consoles[str(number)] = {"kd_mode": mode[0], "screen_sha256": hashlib.sha256(screen).hexdigest()}
    daemons = []
    for path in Path("/proc").glob("[0-9]*/comm"):
        try:
            name = path.read_text().strip()
            executable = Path(os.readlink(path.parent / "exe")).name
            if name in FORBIDDEN or executable in FORBIDDEN:
                daemons.append({"pid": int(path.parent.name), "name": name, "executable": executable})
        except (OSError, ProcessLookupError):
            continue
    return {"consoles": consoles, "consoleblank": Path("/sys/module/kernel/parameters/consoleblank").read_text().strip(),
            "blanked_vt": blanked_vt(fds[1]),
            "power": power_state(), "screensaver_processes": daemons}


def check_snapshot(baseline, current, text_foreground):
    if current["blanked_vt"] in (1, 2):
        raise Mismatch(f"tty{current['blanked_vt']} was blanked")
    for key in ("consoles", "consoleblank"):
        if current[key] != baseline[key]:
            raise Mismatch(f"{key} changed")
    if current["screensaver_processes"]:
        raise Mismatch("A screensaver or console-blanking process is running")
    if text_foreground and current["power"] != baseline["power"]:
        raise Mismatch("Console DPMS or framebuffer power state changed")


class Trace:
    def __init__(self):
        self.path = Path(f"/sys/kernel/tracing/instances/sparky-tty-{os.getpid()}")
        self.path.mkdir()
        self.events = []
        try:
            self.event("sys_enter_ioctl", f"cmd == {TIOCLINUX} && common_pid != {os.getpid()}")
            names = " || ".join(f'filename ~ "*{name}"' for name in sorted(FORBIDDEN))
            self.event("sched_process_exec", names, "sched")
            writers = set()
            for descriptor in Path("/proc").glob("[0-9]*/fd/*"):
                try:
                    if os.readlink(descriptor) in ("/dev/tty1", "/dev/tty2"):
                        pid = int(descriptor.parent.parent.name)
                        if pid != os.getpid():
                            writers.add((pid, int(descriptor.name)))
                except OSError:
                    continue
            if writers:
                writer_filter = " || ".join(f"(common_pid == {pid} && fd == {fd})" for pid, fd in sorted(writers))
                self.event("sys_enter_write", writer_filter)
                self.event("sys_enter_writev", writer_filter)
            (self.path / "tracing_on").write_text("1")
        except Exception:
            self.close()
            raise

    def event(self, name, filter_text, group="syscalls"):
        event = self.path / "events" / group / name
        (event / "filter").write_text(filter_text)
        (event / "enable").write_text("1")
        self.events.append(event)

    def check(self):
        text = (self.path / "trace").read_text()
        rows = [line for line in text.splitlines() if line and not line.startswith("#")]
        if rows:
            raise Mismatch("Unexpected console ioctl, writer or blanking-program execution: " + "\n".join(rows[:10]))
        for stats in self.path.glob("per_cpu/cpu*/stats"):
            for name in ("overrun", "commit overrun", "dropped events"):
                match = re.search(r"^" + name + r":\s*(\d+)", stats.read_text(), re.M)
                if match and int(match[1]):
                    raise RuntimeError("Trace events were lost")

    def close(self):
        (self.path / "tracing_on").write_text("0")
        for event in self.events:
            (event / "enable").write_text("0")
        self.path.rmdir()


def run_probe(args, result):
    if os.geteuid() != 0 or Path("/.dockerenv").exists():
        raise RuntimeError("Run as root in the isolated guest, never a container or the host")
    command("systemd-detect-virt", "--vm")
    sessions = command("loginctl", "list-sessions", "--no-legend").splitlines()
    kde = []
    for row in sessions:
        session = row.split()[0]
        data = command("loginctl", "show-session", session, "-p", "Type", "-p", "Desktop", "-p", "Name", "-p", "VTNr").splitlines()
        props = dict(line.split("=", 1) for line in data)
        if props.get("Type") == "wayland" and props.get("Desktop", "").lower() in ("kde", "plasma"):
            kde.append((session, props))
    if len(kde) != 1:
        raise RuntimeError("Need exactly one Plasma Wayland session")
    session, props = kde[0]
    plasma_vt = int(props["VTNr"])
    if plasma_vt < 3:
        raise RuntimeError("Plasma must use a different VT; tty1 and tty2 must both be text consoles")
    user = pwd.getpwnam(props["Name"])
    runtime = Path(f"/run/user/{user.pw_uid}")
    displays = [str(path) for path in runtime.glob("wayland-*") if path.is_socket()]
    if len(displays) != 1:
        raise RuntimeError("Need exactly one guest Wayland display socket")

    def user_command(*words):
        return command("runuser", "-u", user.pw_name, "--", "env", f"XDG_RUNTIME_DIR={runtime}", *words)

    def powerdevil(method):
        return user_command("busctl", "--user", "call", "org.kde.Solid.PowerManagement",
                            "/org/kde/Solid/PowerManagement", "org.kde.Solid.PowerManagement", method)

    def locked():
        return user_command("busctl", "--user", "call", "org.freedesktop.ScreenSaver",
                            "/ScreenSaver", "org.freedesktop.ScreenSaver", "GetActive") == "b true"

    if powerdevil("currentProfile") != 's "AC"':
        raise RuntimeError("This shortened desktop timeline requires the AC profile")
    fds = {number: os.open(f"/dev/tty{number}", os.O_RDONLY | os.O_NOCTTY) for number in (1, 2)}
    original_vt = active_vt(fds[1])
    config = Path(user.pw_dir) / ".config/powerdevilrc"
    original = config.read_bytes() if config.exists() else None
    original_stat = config.stat() if config.exists() else None
    trace = None
    configured = False
    result["timeline_seconds"] = POINTS
    result["session"] = {"id": session, "plasma_vt": plasma_vt, "profile": "AC"}
    result["samples"] = []
    try:
        for vt in (1, 2):
            activate(fds[1], vt)
            time.sleep(2)
        activate(fds[1], original_vt)
        if not args.negative:
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            parser.optionxform = str
            parser.read_string(original.decode() if original is not None else "")
            group = "AC][Display"
            if not parser.has_section(group):
                parser.add_section(group)
            parser[group]["DimDisplayIdleTimeoutSec"] = "15"
            parser[group]["TurnOffDisplayIdleTimeoutSec"] = "165"
            parser[group]["LockBeforeTurnOffDisplay"] = "true"
            text = io.StringIO()
            parser.write(text, space_around_delimiters=False)
            configured = True
            config.write_text(text.getvalue())
            os.chown(config, user.pw_uid, user.pw_gid)
            powerdevil("reparseConfiguration")
            trace = Trace()

        phases = (2,) if args.negative else (plasma_vt, 1, 2)
        for vt in phases:
            activate(fds[1], vt)
            time.sleep(2)
            baseline = snapshot(fds)
            if baseline["consoleblank"] != "0" or baseline["blanked_vt"] in (1, 2):
                raise RuntimeError("The console baseline is already configured to blank")
            if any(console["kd_mode"] != 0 for console in baseline["consoles"].values()):
                raise RuntimeError("Both tty1 and tty2 must remain in KD_TEXT mode")
            if baseline["screensaver_processes"]:
                raise RuntimeError("A screensaver or console-blanking program is already running")
            text_foreground = vt in (1, 2)
            if vt == plasma_vt:
                initial_dpms = json.loads(user_command(sys.executable, str(Path(__file__).resolve()), "--dpms", displays[0]))
                supported = [output for output in initial_dpms if output["supported"]]
                if not supported or any(output["mode"] != 0 for output in supported) or locked():
                    raise RuntimeError("Start with the guest Plasma session unlocked and its screen on")
                result["native_dpms_baseline"] = initial_dpms
            if text_foreground:
                if not baseline["power"]:
                    raise RuntimeError("No console DPMS/framebuffer power state is readable")
                if any(value != "0" for path, value in baseline["power"].items() if path.endswith("/blank")):
                    raise RuntimeError("The foreground text framebuffer is already blank")
            result["samples"].append({"vt": vt, "point": "baseline", "state": baseline})
            if args.negative:
                fcntl.ioctl(fds[2], TIOCLINUX, bytes([14]))
                current = snapshot(fds)
                result["samples"].append({"vt": 2, "point": "planted-blank", "state": current})
                result["negative_injected"] = current["blanked_vt"] == 2
                if not result["negative_injected"]:
                    raise RuntimeError("The negative control did not actually blank tty2")
                check_snapshot(baseline, current, True)
                raise RuntimeError("The planted change was not detected")

            start = time.monotonic()
            recorded = set()
            while True:
                elapsed = time.monotonic() - start
                current = snapshot(fds)
                check_snapshot(baseline, current, text_foreground)
                trace.check()
                active = command("loginctl", "show-session", session, "-p", "Active", "--value")
                if (active == "yes") != (vt == plasma_vt):
                    raise Mismatch("The active logind session does not match the foreground VT")
                for seconds, point in POINTS.items():
                    if elapsed >= seconds and seconds not in recorded:
                        result["samples"].append({"vt": vt, "point": point, "elapsed": elapsed, "state": current})
                        recorded.add(seconds)
                if vt == plasma_vt and elapsed >= 185 and not result.get("native_kde_screen_off_and_locked"):
                    dpms = json.loads(user_command(sys.executable, str(Path(__file__).resolve()), "--dpms", displays[0]))
                    supported = [output for output in dpms if output["supported"]]
                    if not supported or any(output["mode"] != 3 for output in supported) or not locked():
                        raise Mismatch("The native KDE screen-off and lock did not happen")
                    result["native_kde_screen_off_and_locked"] = True
                    result["native_dpms_after_idle"] = dpms
                if elapsed >= 240:
                    break
                time.sleep(1)
            result.setdefault("completed_vts", []).append(vt)
    finally:
        errors = []

        def cleanup(action):
            try:
                action()
            except Exception as error:
                errors.append(str(error))

        def restore_config():
            if configured:
                if original is None:
                    config.unlink()
                else:
                    config.write_bytes(original)
                    os.chown(config, original_stat.st_uid, original_stat.st_gid)
                    os.chmod(config, original_stat.st_mode & 0o777)
                powerdevil("reparseConfiguration")

        if args.negative:
            cleanup(lambda: fcntl.ioctl(fds[2], TIOCLINUX, bytes([4])))
        if trace is not None:
            cleanup(trace.close)
        cleanup(lambda: activate(fds[1], original_vt))
        cleanup(restore_config)
        for fd in fds.values():
            cleanup(lambda fd=fd: os.close(fd))
        if errors:
            raise RuntimeError("Guest cleanup failed: " + "; ".join(errors))


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--dpms":
        print(json.dumps(DpmsReader(sys.argv[2]).read()))
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--negative", action="store_true")
    args = parser.parse_args()
    result = {"negative": args.negative, "failure": None, "verified": False}
    status = 0
    try:
        run_probe(args, result)
        result["verified"] = True
    except Mismatch as error:
        result["failure"] = str(error)
        result["negative_detected"] = bool(result.get("negative_injected"))
        status = 1
    except Exception as error:
        result["failure"] = str(error)
        status = 2
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
