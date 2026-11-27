#!/usr/bin/python3
# The knob-owner's decisions on recorded machines: what is held, by whom, what each daemon is kept off, what is said.
# Each case builds a machine under a temporary root (sysfs, CoreCtrl's saved profiles in a person's settings folder,
# power-profiles-daemon's state file, LACT's settings, the person's kept choice, and the answers of the bus in fixture/)
# and runs `knob-owner plan` there. CoreCtrl's profiles are written as CoreCtrl 1.5.2 writes them: NAME.ccpro, a zip
# archive holding profile.xml (profilestorage.cpp, ccproparser.cpp), its elements and attributes as its XML parsers write
# them (profilexmlparser.cpp, cpuxmlparser.cpp, gpuxmlparser.cpp, controlmodexmlparser.cpp, cpufreqxmlparser.cpp).
import json
import os
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OWNER = os.environ.get("KNOB_OWNER", os.path.join(HERE, "..", "bin", "knob-owner"))
SLOT = "0000:03:00.0"
LACT_ID = "1002:6660-17AA:3801-" + SLOT
CONFIG = "/home/person/.config"


def write(root, path, text):
    path = os.path.join(root, path.lstrip("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def profile(exe="_global_", name=None, active=True, cpu=True, cpu_mode="CPU_CPUFREQ", cpu_node="mode", gpus=None):
    """CoreCtrl's profile.xml. cpu: the CPU component on or off; cpu_mode: CPU_CPUFREQ or NOOP ("Do not control");
    cpu_node: "mode" (1.5.2), "legacy" (an older profile: the control right under CPU, socketId), None (no CPU element).
    gpus: [(active, index, deviceid, revision, uniqueid, control, mode)]."""
    if gpus is None:
        gpus = [(True, 0, "6660", "83", None, "AMD_PM_PERFMODE", "AMD_PM_AUTO")]
    b = lambda v: "true" if v else "false"
    out = ['<?xml version="1.0"?>', '<PROFILE active="%s" name="%s" exe="%s">' % (b(active), name or exe, exe)]
    if cpu_node == "mode":
        out += ['\t<CPU active="%s" physicalId="0">' % b(cpu),
                '\t\t<CPU_CPUFREQ_MODE active="true" mode="%s">' % cpu_mode,
                '\t\t\t<CPU_CPUFREQ active="%s" scalingGovernor="performance" eppHint="balance_performance" />' % b(cpu_mode == "CPU_CPUFREQ"),
                '\t\t\t<NOOP active="%s" />' % b(cpu_mode == "NOOP"), '\t\t</CPU_CPUFREQ_MODE>', '\t</CPU>']
    elif cpu_node == "legacy":
        out += ['\t<CPU active="%s" socketId="0">' % b(cpu), '\t\t<CPU_CPUFREQ active="true" scalingGovernor="performance" />', '\t</CPU>']
    for active_, index, dev, rev, unique, control, mode in gpus:
        out += ['\t<GPU active="%s" index="%d" deviceid="%s" revision="%s"%s>' % (b(active_), index, dev, rev, ' uniqueid="%s"' % unique if unique else ""),
                '\t\t<%s active="true" mode="%s">' % (control, mode), '\t\t\t<NOOP active="%s" />' % b(mode == "NOOP"),
                '\t\t</%s>' % control, '\t</GPU>']
    out.append('</PROFILE>')
    return "\n".join(out) + "\n"


def machine(cpu="acpi-cpufreq", cards=None, corectrl="no", profiles=None, apps=(), lactd="inactive", lact=None, ppd="inactive",
            dpm=None, live=None, tuned="inactive", record=None, person=None):
    """cards: [(card, slot, driver, vendor, render index, PCI_ID, revision, unique_id or None)]; profiles: {file name: text}
    (None: CoreCtrl's folder is not known); live: the running daemon's amdgpu_dpm, "on" or "off"."""
    if cards is None:
        cards = [("card0", SLOT, "amdgpu", "0x1002", 0, "1002:6660", "0x83", None)]
    root = tempfile.mkdtemp(prefix="knob-owner-")
    write(root, "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor", "schedutil\n")
    if cpu in ("amd_pstate", "intel_pstate"):
        write(root, "/sys/devices/system/cpu/%s/status" % cpu, "active\n")
        write(root, "/sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference", "balance_performance\n")
    for card, slot, driver, vendor, render, pci, revision, unique in cards:
        dev = os.path.join(root, "sys/devices/pci0000:00", slot)
        write(root, "/sys/devices/pci0000:00/%s/vendor" % slot, vendor + "\n")
        write(root, "/sys/devices/pci0000:00/%s/uevent" % slot, "DRIVER=%s\nPCI_ID=%s\nPCI_SLOT_NAME=%s\n" % (driver, pci, slot))
        write(root, "/sys/devices/pci0000:00/%s/revision" % slot, revision + "\n")
        if unique:
            write(root, "/sys/devices/pci0000:00/%s/unique_id" % slot, unique + "\n")
        os.makedirs(os.path.join(root, "sys/bus/pci/drivers", driver), exist_ok=True)
        os.symlink(os.path.relpath(os.path.join(root, "sys/bus/pci/drivers", driver), dev), os.path.join(dev, "driver"))
        for node in (card, "renderD%d" % (128 + render)):
            os.makedirs(os.path.join(root, "sys/class/drm", node), exist_ok=True)
            os.symlink(os.path.relpath(dev, os.path.join(root, "sys/class/drm", node)), os.path.join(root, "sys/class/drm", node, "device"))
    if profiles is not None:
        folder = os.path.join(root, CONFIG.lstrip("/"), "corectrl", "profiles")
        os.makedirs(folder)
        for name, text in profiles.items():
            path = os.path.join(folder, name)
            if text.startswith("<?xml"):
                with zipfile.ZipFile(path, "w") as z:
                    z.writestr("profile.xml", text)
            else:
                with open(path, "w") as f:
                    f.write(text)
        write(root, "/fixture/corectrl-config", CONFIG + "\n")
    write(root, "/fixture/corectrl-apps", "".join(a + "\n" for a in apps))
    if lact is not None:
        write(root, "/etc/lact/config.yaml", lact)
    if dpm is not None:
        write(root, "/var/lib/power-profiles-daemon/state.ini", "[State]\nProfile=balanced\n\n[Actions]\namdgpu_dpm=%s\n" % dpm)
    if record is not None:
        write(root, "/var/lib/sparky-stereo-corectrl/ppd-actions-off.json", record)
    if person is not None:
        write(root, "/var/lib/sparky-stereo-corectrl/ppd-actions.json", person)
    if live is not None:
        write(root, "/fixture/ppd-amdgpu_dpm", live + "\n")
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
BLOCK = ["--block-driver=amd_pstate", "--block-driver=intel_pstate"]
GPU_OFF = [(True, 0, "6660", "83", None, "AMD_PM_PERFMODE", "NOOP")]
GPU_ON = [(True, 0, "6660", "83", None, "AMD_PM_PERFMODE", "AMD_PM_AUTO")]
G = "_global_.ccpro"
ON, OFF = {"amdgpu_dpm": True}, {"amdgpu_dpm": False}
CPU_NOTICE = {"cpu": ["LOCAL2", "CoreCtrl"]}
CARD_NOTICE = {"card-" + KEY: ["LOCAL3", "CoreCtrl", CARD]}

CASES = [
    # name, machine, what the plan must say (only the keys given are compared)
    ("a10: no processor driver of power-profiles-daemon, amdgpu_dpm off, CoreCtrl with its defaults",
     machine(corectrl="started", profiles={G: profile()}, ppd="active"),
     dict(ppd_args=[], ppd_actions_off=[], ppd_actions=OFF, tuned_cpu=False, notices={})),
    ("zen: amd_pstate, CoreCtrl's processor control on", machine(cpu="amd_pstate", corectrl="started", profiles={G: profile()}, ppd="active"),
     dict(ppd_args=BLOCK, notices=CPU_NOTICE)),
    ("zen: CoreCtrl's processor control set to Do not control: power-profiles-daemon keeps its driver",
     machine(cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP")}, ppd="active"),
     dict(ppd_args=[], notices={}, holders={"0000:03:00.0": ["CoreCtrl"]})),
    ("zen: CoreCtrl's CPU component off", machine(cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu=False)}, ppd="active"),
     dict(ppd_args=[], notices={})),
    ("zen: amd_pstate, CoreCtrl not running", machine(cpu="amd_pstate", profiles={G: profile()}, ppd="active"), dict(ppd_args=[], notices={})),
    ("intel_pstate, CoreCtrl's processor control on", machine(cpu="intel_pstate", corectrl="started", profiles={G: profile()}, ppd="active"),
     dict(ppd_args=BLOCK, notices=CPU_NOTICE)),
    ("amdgpu_dpm on, CoreCtrl's card power control on: off while held",
     machine(corectrl="started", profiles={G: profile()}, ppd="active", live="on"),
     dict(ppd_actions_off=["amdgpu_dpm"], ppd_actions=OFF, notices=CARD_NOTICE)),
    ("amdgpu_dpm on, the card's power control set to Do not control: the action stays the person's",
     machine(corectrl="started", profiles={G: profile(gpus=GPU_OFF)}, ppd="active", live="on"),
     dict(ppd_actions_off=[], ppd_actions=ON, notices={}, holders={"cpu": ["CoreCtrl"]})),
    ("both on, amd_pstate, amdgpu_dpm on: as before", machine(cpu="amd_pstate", corectrl="started", profiles={G: profile()}, ppd="active", live="on"),
     dict(ppd_args=BLOCK, ppd_actions_off=["amdgpu_dpm"], ppd_actions=OFF, notices=dict(CPU_NOTICE, **CARD_NOTICE))),
    ("both off, amd_pstate, amdgpu_dpm on: nothing held",
     machine(cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP", gpus=GPU_OFF)}, ppd="active", live="on"),
     dict(ppd_args=[], ppd_actions=ON, notices={}, holders={})),
    ("amdgpu_dpm off in the state file, CoreCtrl's card control on", machine(corectrl="started", profiles={G: profile()}, ppd="active", dpm="false", live="off"),
     dict(ppd_actions_off=[], ppd_actions=OFF, notices={})),
    ("CoreCtrl's folder not found: its defaults (all on)", machine(cpu="amd_pstate", corectrl="started", ppd="active", live="on"),
     dict(ppd_args=BLOCK, ppd_actions_off=["amdgpu_dpm"])),
    ("an unreadable profile is left out, as CoreCtrl leaves it out: the global's defaults",
     machine(cpu="amd_pstate", corectrl="started", profiles={G: "not a zip archive\n"}, ppd="active"), dict(ppd_args=BLOCK)),
    ("an older profile (the control right under CPU, socketId): on", machine(cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_node="legacy")}, ppd="active"),
     dict(ppd_args=BLOCK)),
    ("a profile without a CPU element: CoreCtrl's default, on", machine(cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_node=None)}, ppd="active"),
     dict(ppd_args=BLOCK)),
    # programs with a profile (the helper's appExec / appExit)
    ("a program's profile with the processor on, the program running", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP"), "game.ccpro": profile(exe="game")}, apps=["game"], ppd="active"),
     dict(ppd_args=BLOCK, notices=CPU_NOTICE)),
    ("the same program not running", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP"), "game.ccpro": profile(exe="game")}, ppd="active"),
     dict(ppd_args=[])),
    ("the program's profile turned off in CoreCtrl", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP"), "game.ccpro": profile(exe="game", active=False)}, apps=["game"],
        ppd="active"), dict(ppd_args=[])),
    ("the program's CPU component off: taken from the global profile (off)", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP"), "game.ccpro": profile(exe="game", cpu=False)}, apps=["game"],
        ppd="active"), dict(ppd_args=[])),
    ("the program's CPU component off: taken from the global profile (on)", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(), "game.ccpro": profile(exe="game", cpu=False, cpu_mode="NOOP")}, apps=["game"],
        ppd="active"), dict(ppd_args=BLOCK)),
    ("two programs: the one started last decides (Do not control)", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP"), "a.ccpro": profile(exe="a"), "b.ccpro": profile(exe="b", cpu_mode="NOOP")},
        apps=["a", "b"], ppd="active"), dict(ppd_args=[])),
    ("two programs: the one started last decides (on)", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP"), "a.ccpro": profile(exe="a"), "b.ccpro": profile(exe="b", cpu_mode="NOOP")},
        apps=["b", "a"], ppd="active"), dict(ppd_args=BLOCK)),
    ("a program's profile holds the card while it runs", machine(
        corectrl="started", profiles={G: profile(gpus=GPU_OFF), "game.ccpro": profile(exe="game", gpus=GPU_ON)}, apps=["game"], ppd="active", live="on"),
     dict(ppd_actions=OFF, ppd_actions_off=["amdgpu_dpm"], notices=CARD_NOTICE)),
    # manual profiles: kept in CoreCtrl's memory only, so said, not held
    ("a manual profile with the processor on: said, not held", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP", gpus=GPU_OFF), "_manual_games.ccpro": profile(exe="_manual_", name="games", gpus=GPU_OFF)},
        ppd="active", live="on"), dict(ppd_args=[], ppd_actions=ON, notices={"manual-cpu-games": ["LOCAL13", "games"]})),
    ("a manual profile with the card on: said, the action stays the person's", machine(
        corectrl="started", profiles={G: profile(gpus=GPU_OFF), "_manual_games.ccpro": profile(exe="_manual_", name="games")}, ppd="active", live="on"),
     dict(ppd_actions=ON, notices={"manual-card-games-" + KEY: ["LOCAL14", "games", CARD]})),
    ("a manual profile that adds nothing to what is held: nothing said", machine(
        cpu="amd_pstate", corectrl="started", profiles={G: profile(), "_manual_games.ccpro": profile(exe="_manual_", name="games")}, ppd="active", live="on"),
     dict(ppd_args=BLOCK, notices=dict(CPU_NOTICE, **CARD_NOTICE))),
    # which GPU element is the card's (gpuxmlparser.cpp)
    ("the card's element is matched by its unique id", machine(
        cards=[("card0", SLOT, "amdgpu", "0x1002", 0, "1002:6660", "0x83", "aa11")], corectrl="started",
        profiles={G: profile(gpus=[(True, 5, "FFFF", "00", "AA11", "AMD_PM_PERFMODE", "NOOP")])}, ppd="active", live="on"),
     dict(ppd_actions=ON, holders={"cpu": ["CoreCtrl"]})),
    ("an element with another unique id is not the card's: CoreCtrl's defaults (on)", machine(
        cards=[("card0", SLOT, "amdgpu", "0x1002", 0, "1002:6660", "0x83", "aa11")], corectrl="started",
        profiles={G: profile(gpus=[(True, 0, "6660", "83", "BB22", "AMD_PM_PERFMODE", "NOOP")])}, ppd="active", live="on"),
     dict(ppd_actions=OFF, ppd_actions_off=["amdgpu_dpm"])),
    ("an element of another card (index 1): this card has CoreCtrl's defaults (on)", machine(
        corectrl="started", profiles={G: profile(gpus=[(True, 1, "6660", "83", None, "AMD_PM_PERFMODE", "NOOP")])}, ppd="active", live="on"),
     dict(ppd_actions=OFF)),
    ("two cards, one held: the action is off for both (one switch), said for the held one", machine(
        cards=[("card0", SLOT, "amdgpu", "0x1002", 0, "1002:6660", "0x83", None), ("card1", "0000:00:01.0", "amdgpu", "0x1002", 1, "1002:9874", "0xc4", None)],
        corectrl="started", profiles={G: profile(gpus=GPU_ON + [(True, 1, "9874", "C4", None, "AMD_PM_PERFMODE", "NOOP")])}, ppd="active", live="on"),
     dict(ppd_actions=OFF, holders={"cpu": ["CoreCtrl"], SLOT: ["CoreCtrl"]}, notices=CARD_NOTICE)),
    # the person's choice of amdgpu_dpm (kept here; LACT's start-up "off" is not the person's)
    ("LACT turned the action off at its start, the state file says on: the person's on comes back",
     machine(lactd="active", lact=LACT_EMPTY, ppd="active", dpm="true", live="off"), dict(ppd_actions=ON, notices={})),
    ("the person's kept choice wins over the state file", machine(ppd="active", dpm="false", live="off", person='{"amdgpu_dpm": true}'),
     dict(ppd_actions=ON)),
    ("0.1.0's record is the person's choice", machine(corectrl="started", profiles={G: profile()}, ppd="active", dpm="false", live="off",
                                                       record='{"amdgpu_dpm": true}'),
     dict(ppd_actions=OFF, ppd_actions_off=["amdgpu_dpm"], notices=CARD_NOTICE)),
    ("no state file, the action off: its default (off)", machine(ppd="active", live="off"), dict(ppd_actions=OFF)),
    ("the person kept it off: it stays off", machine(ppd="active", live="off", dpm="true", person='{"amdgpu_dpm": false}'), dict(ppd_actions=OFF)),
    # LACT
    ("LACT holds the card (default list), amdgpu_dpm on", machine(lactd="active", lact=LACT_DEFAULT, ppd="active", live="on"),
     dict(ppd_actions_off=["amdgpu_dpm"], ppd_actions=OFF, notices={"card-" + KEY: ["LOCAL3", "LACT", CARD]})),
    ("LACT holds the card (current profile), amdgpu_dpm on", machine(lactd="active", lact=LACT_PROFILE, ppd="active", live="on"),
     dict(ppd_actions_off=["amdgpu_dpm"], notices={"card-" + KEY: ["LOCAL3", "LACT", CARD]})),
    ("LACT's settings name another card", machine(lactd="active", lact=LACT_OTHER, ppd="active", live="on"), dict(ppd_actions=ON, notices={})),
    ("LACT with no card settings (as installed)", machine(lactd="active", lact=LACT_EMPTY, ppd="active", live="on"), dict(ppd_actions=ON, notices={})),
    ("lactd stopped", machine(lactd="inactive", lact=LACT_DEFAULT, ppd="active", live="on"), dict(ppd_actions=ON, notices={})),
    ("CoreCtrl and LACT on one card", machine(corectrl="started", profiles={G: profile()}, lactd="active", lact=LACT_DEFAULT, ppd="active"),
     dict(notices={"both-" + KEY: ["LOCAL4", "CoreCtrl", "LACT", CARD]})),
    ("CoreCtrl's card control off, LACT holds the card: no conflict", machine(corectrl="started", profiles={G: profile(gpus=GPU_OFF)}, lactd="active",
                                                                            lact=LACT_DEFAULT, ppd="active", live="on"),
     dict(holders={"cpu": ["CoreCtrl"], SLOT: ["LACT"]}, notices={"card-" + KEY: ["LOCAL3", "LACT", CARD]})),
    ("LACT's settings unreadable", machine(lactd="active", lact="gpus: [\n", ppd="active"), dict(notices={"lact-config": ["LOCAL8", "/etc/lact/config.yaml"]})),
    # tuned
    ("tuned instead of power-profiles-daemon, CoreCtrl's processor control on",
     machine(cpu="amd_pstate", corectrl="started", profiles={G: profile()}, ppd="absent", tuned="active"), dict(ppd_args=[], tuned_cpu=True, notices=CPU_NOTICE)),
    ("tuned, CoreCtrl's processor control set to Do not control: tuned keeps the processors",
     machine(cpu="amd_pstate", corectrl="started", profiles={G: profile(cpu_mode="NOOP")}, ppd="absent", tuned="active"), dict(tuned_cpu=False, notices={})),
    ("tuned with a radeon card, CoreCtrl's power state control on", machine(
        cards=[("card0", SLOT, "radeon", "0x1002", 0, "1002:6660", "0x83", None)], corectrl="started",
        profiles={G: profile(gpus=[(True, 0, "6660", "83", None, "AMD_PM_POWERSTATE_MODE", "AMD_PM_POWERSTATE")])}, ppd="absent", tuned="active"),
     dict(tuned_cpu=True, notices={"cpu": ["LOCAL2", "CoreCtrl"], "tuned-radeon-" + KEY: ["LOCAL6", CARD, "CoreCtrl"]})),
    ("tuned with a radeon card, its power state control set to Do not control", machine(
        cards=[("card0", SLOT, "radeon", "0x1002", 0, "1002:6660", "0x83", None)], corectrl="started",
        profiles={G: profile(gpus=[(True, 0, "6660", "83", None, "AMD_PM_POWERSTATE_MODE", "NOOP")])}, ppd="absent", tuned="active"),
     dict(notices={"cpu": ["LOCAL2", "CoreCtrl"]})),
    ("an NVIDIA card is not an AMD card", machine(cards=[("card0", SLOT, "nvidia", "0x10de", 0, "10DE:2504", "0xa1", None)], corectrl="started",
                                                  profiles={G: profile()}, ppd="active", live="on"),
     dict(ppd_actions=ON, notices={})),
    ("power-profiles-daemon not installed, no tuned", machine(cpu="amd_pstate", corectrl="started", profiles={G: profile()}, ppd="absent"),
     dict(ppd_args=[], notices={})),
]


def main():
    failed = 0
    for name, root, want in CASES:
        got = plan(root)
        bad = {k: (v, got.get(k)) for k, v in want.items() if got.get(k) != v}
        print("%s  %s" % ("ok  " if not bad else "FAIL", name))
        if bad:
            failed += 1
            for k, (v, g) in bad.items():
                print("      %s: want %s\n      %s  got  %s" % (k, v, " " * len(k), g))
    print("%d of %d cases failed" % (failed, len(CASES)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
