#!/usr/bin/python3
# The knob-owner's decisions on recorded machines: what is held, by whom, what each daemon is kept off, what is said.
# Each case builds a machine under a temporary root (sysfs, power-profiles-daemon's state file, LACT's settings, and the
# answers of the bus in fixture/) and runs `knob-owner plan` there.
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OWNER = os.environ.get("KNOB_OWNER", os.path.join(HERE, "..", "bin", "knob-owner"))
SLOT = "0000:03:00.0"
LACT_ID = "1002:6660-17AA:3801-" + SLOT


def write(root, path, text):
    path = os.path.join(root, path.lstrip("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def machine(cpu="acpi-cpufreq", cards=(("card0", SLOT, "amdgpu", "0x1002"),), corectrl="no", lactd="inactive", lact=None,
            ppd="inactive", dpm=None, tuned="inactive"):
    root = tempfile.mkdtemp(prefix="knob-owner-")
    write(root, "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor", "schedutil\n")
    if cpu in ("amd_pstate", "intel_pstate"):
        write(root, "/sys/devices/system/cpu/%s/status" % cpu, "active\n")
        write(root, "/sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference", "balance_performance\n")
    for card, slot, driver, vendor in cards:
        dev = os.path.join(root, "sys/devices/pci0000:00", slot)
        write(root, "/sys/devices/pci0000:00/%s/vendor" % slot, vendor + "\n")
        os.makedirs(os.path.join(root, "sys/bus/pci/drivers", driver), exist_ok=True)
        os.symlink(os.path.relpath(os.path.join(root, "sys/bus/pci/drivers", driver), dev), os.path.join(dev, "driver"))
        os.makedirs(os.path.join(root, "sys/class/drm", card), exist_ok=True)
        os.symlink(os.path.relpath(dev, os.path.join(root, "sys/class/drm", card)), os.path.join(root, "sys/class/drm", card, "device"))
    if lact is not None:
        write(root, "/etc/lact/config.yaml", lact)
    if dpm is not None:
        write(root, "/var/lib/power-profiles-daemon/state.ini", "[State]\nProfile=balanced\n\n[Actions]\namdgpu_dpm=%s\n" % dpm)
    for name, value in (("corectrl", corectrl), ("lactd", lactd), ("power-profiles-daemon", ppd), ("tuned", tuned)):
        write(root, "/fixture/" + name, value + "\n")
    return root


def plan(root):
    out = subprocess.run([sys.executable, OWNER, "plan"], env=dict(os.environ, SPARKY_KNOB_ROOT=root), capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("knob-owner plan failed: %s" % out.stderr)
    return json.loads(out.stdout)


LACT_DEFAULT = "version: 7\ndaemon:\n  log_level: info\napply_settings_timer: 5\ngpus:\n  %s:\n    fan_control_enabled: false\n    performance_level: low\n" % LACT_ID
LACT_PROFILE = ("version: 7\ndaemon:\n  log_level: info\ncurrent_profile: games\nprofiles:\n  games:\n    gpus:\n      '%s':\n"
                "        performance_level: high\n" % LACT_ID)
LACT_OTHER = "version: 7\ndaemon:\n  log_level: info\ngpus:\n  1002:1234-0000:0000-0000:09:00.0:\n    performance_level: low\n"
LACT_EMPTY = "version: 7\ndaemon:\n  log_level: info\n  admin_group: wheel\napply_settings_timer: 5\ncurrent_profile: null\n"
CARD = "card0 (PCI %s)" % SLOT
KEY = "0000-03-00.0"

CASES = [
    # name, machine, ppd_args, tuned_cpu, notices
    ("a10: no processor driver of power-profiles-daemon, amdgpu_dpm off, CoreCtrl running",
     machine(corectrl="started", ppd="active"), [], False, {}),
    ("zen: amd_pstate active, CoreCtrl running", machine(cpu="amd_pstate", corectrl="started", ppd="active"),
     ["--block-driver=amd_pstate", "--block-driver=intel_pstate"], False, {"cpu": ["LOCAL2", "CoreCtrl"]}),
    ("zen: amd_pstate active, CoreCtrl not running", machine(cpu="amd_pstate", ppd="active"), [], False, {}),
    ("intel_pstate active, CoreCtrl running", machine(cpu="intel_pstate", corectrl="started", ppd="active"),
     ["--block-driver=amd_pstate", "--block-driver=intel_pstate"], False, {"cpu": ["LOCAL2", "CoreCtrl"]}),
    ("amdgpu_dpm turned on, CoreCtrl running", machine(corectrl="started", ppd="active", dpm="true"),
     ["--block-action=amdgpu_dpm"], False, {"card-" + KEY: ["LOCAL3", "CoreCtrl", CARD]}),
    ("amdgpu_dpm turned off in the state file, CoreCtrl running", machine(corectrl="started", ppd="active", dpm="false"), [], False, {}),
    ("LACT holds the card (default list), amdgpu_dpm on", machine(lactd="active", lact=LACT_DEFAULT, ppd="active", dpm="true"),
     ["--block-action=amdgpu_dpm"], False, {"card-" + KEY: ["LOCAL3", "LACT", CARD]}),
    ("LACT holds the card (current profile), amdgpu_dpm on", machine(lactd="active", lact=LACT_PROFILE, ppd="active", dpm="true"),
     ["--block-action=amdgpu_dpm"], False, {"card-" + KEY: ["LOCAL3", "LACT", CARD]}),
    ("LACT's settings name another card", machine(lactd="active", lact=LACT_OTHER, ppd="active", dpm="true"), [], False, {}),
    ("LACT with no card settings (as installed)", machine(lactd="active", lact=LACT_EMPTY, ppd="active", dpm="true"), [], False, {}),
    ("lactd stopped", machine(lactd="inactive", lact=LACT_DEFAULT, ppd="active", dpm="true"), [], False, {}),
    ("CoreCtrl and LACT on one card", machine(corectrl="started", lactd="active", lact=LACT_DEFAULT, ppd="active"), [], False,
     {"both-" + KEY: ["LOCAL4", "CoreCtrl", "LACT", CARD]}),
    ("LACT's settings unreadable", machine(lactd="active", lact="gpus: [\n", ppd="active"), [], False,
     {"lact-config": ["LOCAL8", "/etc/lact/config.yaml"]}),
    ("tuned instead of power-profiles-daemon, CoreCtrl running", machine(cpu="amd_pstate", corectrl="started", ppd="absent", tuned="active"),
     [], True, {"cpu": ["LOCAL2", "CoreCtrl"]}),
    ("tuned with a radeon card, CoreCtrl running", machine(cards=(("card0", SLOT, "radeon", "0x1002"),), corectrl="started", ppd="absent", tuned="active"),
     [], True, {"cpu": ["LOCAL2", "CoreCtrl"], "tuned-radeon-" + KEY: ["LOCAL6", CARD, "CoreCtrl"]}),
    ("an NVIDIA card is not an AMD card", machine(cards=(("card0", SLOT, "nvidia", "0x10de"),), corectrl="started", ppd="active", dpm="true"),
     [], False, {}),
    ("power-profiles-daemon not installed, no tuned", machine(cpu="amd_pstate", corectrl="started", ppd="absent"), [], False, {}),
]


def main():
    failed = 0
    for name, root, ppd, tuned, notices in CASES:
        got = plan(root)
        ok = got["ppd_args"] == ppd and got["tuned_cpu"] == tuned and got["notices"] == notices
        print("%s  %s" % ("ok  " if ok else "FAIL", name))
        if not ok:
            failed += 1
            print("      want ppd %s tuned %s notices %s" % (ppd, tuned, notices))
            print("      got  ppd %s tuned %s notices %s" % (got["ppd_args"], got["tuned_cpu"], got["notices"]))
    print("%d of %d cases failed" % (failed, len(CASES)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
