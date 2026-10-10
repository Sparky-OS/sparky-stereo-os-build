#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the packaged helper against the real PPD on a private container bus."""

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def polkit():
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    name = dbus.service.BusName("org.freedesktop.PolicyKit1", bus)

    class Authority(dbus.service.Object):
        @dbus.service.method("org.freedesktop.PolicyKit1.Authority",
                             in_signature="(sa{sv})sa{ss}us", out_signature="(bba{ss})")
        def CheckAuthorization(self, subject, action, details, flags, cancellation):
            return (True, False, {})

    authority = Authority(name, "/org/freedesktop/PolicyKit1/Authority")
    print("READY", flush=True)
    GLib.MainLoop().run()


if len(sys.argv) > 1 and sys.argv[1] == "--polkit":
    polkit()
    sys.exit(0)

from gi.repository import Gio, GLib

NAME = "org.freedesktop.UPower.PowerProfiles"
IFACE = NAME
OBJECT = "/org/freedesktop/UPower/PowerProfiles"


def property_value(key):
    connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    return connection.call_sync(NAME, OBJECT, "org.freedesktop.DBus.Properties", "Get",
                                GLib.Variant("(ss)", (IFACE, key)), None,
                                Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


if len(sys.argv) > 1 and sys.argv[1] == "--game":
    ready, gate, code, *arguments = sys.argv[2:]
    Path(ready).write_text(json.dumps({"profile": property_value("ActiveProfile"),
                                     "arguments": arguments, "pid": os.getpid()}))
    while not Path(gate).exists():
        time.sleep(0.02)
    sys.exit(int(code))

assert Path("/.dockerenv").exists(), "Run inside Docker"
helper, native_root, output_dir = map(Path, sys.argv[1:])
helper, native_root, output_dir = helper.resolve(), native_root.resolve(), output_dir.resolve()
output_dir.mkdir(parents=True, exist_ok=True)
ctl = native_root / "usr/bin/powerprofilesctl"
daemon = native_root / "usr/libexec/power-profiles-daemon"
env = os.environ.copy()
env["PATH"] = str(ctl.parent) + ":" + env["PATH"]
env["UMOCKDEV_DIR"] = str(output_dir)
env["POWER_PROFILE_DAEMON_FAKE_DRIVER"] = "1"
children = []
logs = []
checks = []
ppd = None


def run(*arguments, check=True):
    return subprocess.run([str(arg) for arg in arguments], env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def eventually(predicate):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except GLib.Error:
            pass
        time.sleep(0.03)
    raise AssertionError("Expected state was not reached within ten seconds")


def start_daemon(fake=True):
    global ppd
    child_env = env.copy()
    if not fake:
        child_env.pop("POWER_PROFILE_DAEMON_FAKE_DRIVER")
    log = (output_dir / ("ppd-fake.log" if fake else "ppd-placeholder.log")).open("w")
    logs.append(log)
    ppd = subprocess.Popen([str(daemon), "-r", "-v", "--disable-upower", "--disable-logind",
                            "--block-driver=amd_pstate", "--block-driver=intel_pstate",
                            "--block-driver=platform_profile", "--block-action=amdgpu_dpm",
                            "--block-action=amdgpu_panel_power", "--block-action=trickle_charge"],
                           env=child_env, stdout=log, stderr=log)
    children.append(ppd)
    eventually(lambda: bool(property_value("Profiles")))


def stop_daemon():
    ppd.terminate()
    ppd.wait(timeout=5)


def start_game(label, code=0, arguments=()):
    ready = output_dir / (label + ".json")
    gate = output_dir / (label + ".exit")
    ready.unlink(missing_ok=True)
    gate.unlink(missing_ok=True)
    process = subprocess.Popen([str(helper), sys.executable, str(Path(__file__).resolve()),
                                "--game", str(ready), str(gate), str(code), *arguments], env=env)
    children.append(process)
    eventually(ready.exists)
    return process, gate, json.loads(ready.read_text())


def restored(profile):
    eventually(lambda: property_value("ActiveProfile") == profile
               and not property_value("ActiveProfileHolds"))


try:
    bus = run("dbus-daemon", "--session", "--fork", "--print-address", "--print-pid")
    address, bus_pid = bus.stdout.strip().splitlines()
    env["DBUS_SYSTEM_BUS_ADDRESS"] = address
    os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = address
    polkit_log = (output_dir / "polkit.log").open("w")
    logs.append(polkit_log)
    authority = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--polkit"],
                                 env=env, stdout=polkit_log, stderr=polkit_log)
    children.append(authority)
    eventually(lambda: "READY" in (output_dir / "polkit.log").read_text())
    start_daemon()
    assert property_value("Version") == "0.30"

    for base in ("balanced", "power-saver"):
        run(ctl, "set", base)
        process, gate, state = start_game(base, arguments=("space in argument", "$(false)", "line\nbreak"))
        assert state["profile"] == "performance", state
        assert state["arguments"] == ["space in argument", "$(false)", "line\nbreak"], state
        holds = property_value("ActiveProfileHolds")
        assert len(holds) == 1 and holds[0]["ApplicationId"] == "org.sparkylinux.SparkyStereo.GamePerformance", holds
        gate.touch()
        assert process.wait(timeout=10) == 0
        restored(base)
        checks.append(f"hold, arguments and restoration from {base}")

    run(ctl, "set", "balanced")
    process, gate, state = start_game("nonzero", code=37)
    assert state["profile"] == "performance"
    gate.touch()
    assert process.wait(timeout=10) == 37
    restored("balanced")
    checks.append("child exit 37 and restoration")

    for sig in (signal.SIGTERM, signal.SIGKILL):
        process, gate, state = start_game(sig.name)
        assert state["profile"] == "performance"
        process.send_signal(sig)
        assert process.wait(timeout=10) == -sig
        restored("balanced")
        if sig == signal.SIGKILL:
            os.kill(state["pid"], signal.SIGTERM)
        checks.append(f"{sig.name} disconnect releases hold")

    first, first_gate, first_state = start_game("concurrent-first")
    second, second_gate, second_state = start_game("concurrent-second")
    assert first_state["profile"] == second_state["profile"] == "performance"
    assert len(property_value("ActiveProfileHolds")) == 2
    first_gate.touch()
    assert first.wait(timeout=10) == 0
    eventually(lambda: len(property_value("ActiveProfileHolds")) == 1)
    assert property_value("ActiveProfile") == "performance"
    saver = subprocess.Popen([str(ctl), "launch", "-p", "power-saver", "--", "sleep", "60"], env=env)
    children.append(saver)
    eventually(lambda: property_value("ActiveProfile") == "power-saver")
    saver.terminate()
    assert saver.wait(timeout=10) == -signal.SIGTERM
    eventually(lambda: property_value("ActiveProfile") == "performance")
    second_gate.touch()
    assert second.wait(timeout=10) == 0
    restored("balanced")
    checks.append("concurrent games and power-saver hold precedence")

    assert run(helper, check=False).returncode == 2
    assert not property_value("ActiveProfileHolds")
    checks.append("no command fails without a hold")
    missing = run(helper, "/nonexistent/sparky-game", check=False)
    assert missing.returncode != 0
    restored("balanced")
    checks.append("failed command spawn releases hold")

    stop_daemon()
    start_daemon(fake=False)
    assert "performance" not in [profile["Profile"] for profile in property_value("Profiles")]
    fallback = run(helper, sys.executable, "-c", "import sys; print(sys.argv[1]); sys.exit(7)",
                   "argument with spaces", check=False)
    assert fallback.returncode == 7 and fallback.stdout.strip() == "argument with spaces", fallback
    assert not property_value("ActiveProfileHolds")
    checks.append("unsupported performance executes unchanged")
    stop_daemon()
    fallback = run(helper, sys.executable, "-c", "import sys; sys.exit(9)", check=False)
    assert fallback.returncode == 9 and "Failed to communicate" in fallback.stderr, fallback
    checks.append("unavailable daemon executes unchanged")

except Exception as error:
    (output_dir / "results.json").write_text(json.dumps({"passed": checks, "failure": str(error)}, indent=2) + "\n")
    raise
else:
    (output_dir / "results.json").write_text(json.dumps({"passed": checks, "failure": None}, indent=2) + "\n")
finally:
    for child in reversed(children):
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    for log in logs:
        log.close()
    if "bus_pid" in locals():
        os.kill(int(bus_pid), signal.SIGTERM)
