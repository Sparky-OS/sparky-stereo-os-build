#!/usr/bin/python3
# The person's choice of power-profiles-daemon's amdgpu_dpm action, kept by the knob-owner: where it comes from when nothing
# is kept yet, 0.1.0's record carried over, and who a change is taken from. LACT turns the action off at every start
# (lact-daemon/src/system/power_profiles_daemon.rs, from Server::new) and the daemon would save that "off" as the person's
# at its next profile change; a change by LACT or by the knob-owner itself is never the person's. The bus is a stand-in.
import importlib.machinery
import importlib.util
import json
import os
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OWNER = os.environ.get("KNOB_OWNER", os.path.join(HERE, "..", "bin", "knob-owner"))
root = tempfile.mkdtemp(prefix="knob-person-")
os.environ["SPARKY_KNOB_ROOT"] = root
os.makedirs(root + "/fixture")
stub = os.path.join(root, "bin")
os.makedirs(stub)
with open(os.path.join(stub, "sparky-stereo-problems"), "w") as f:
    f.write("#!/bin/sh\nexit 0\n")
os.chmod(os.path.join(stub, "sparky-stereo-problems"), stat.S_IRWXU)
os.environ["PATH"] = stub + ":" + os.environ["PATH"]
loader = importlib.machinery.SourceFileLoader("knob_owner", OWNER)
ko = importlib.util.module_from_spec(importlib.util.spec_from_loader("knob_owner", loader))
loader.exec_module(ko)
failed = 0


def check(name, got, want):
    global failed
    ok = got == want
    failed += not ok
    print("%s  %s" % ("ok  " if ok else "FAIL", name))
    if not ok:
        print("      want %s\n      got  %s" % (want, got))


def state_file(value):
    os.makedirs(os.path.dirname(ko.PPD_STATE), exist_ok=True)
    if value is None:
        if os.path.exists(ko.PPD_STATE):
            os.unlink(ko.PPD_STATE)
        return
    with open(ko.PPD_STATE, "w") as f:
        f.write("[State]\nProfile=balanced\n\n[Actions]\namdgpu_dpm=%s\n" % value)


def kept(data):
    for path in (ko.PERSON, ko.OLD_RECORD):
        if os.path.exists(path):
            os.unlink(path)
    if data is not None:
        ko.write_json(ko.PERSON, data)


# where the person's choice comes from
kept(None); state_file(None)
check("nothing kept, no state file, the action off: the default (off)", ko.person_choice("amdgpu_dpm", False), (False, "default"))
check("nothing kept, the running daemon has it on: on (only a person turns it on)", ko.person_choice("amdgpu_dpm", True), (True, "running daemon"))
state_file("true")
check("nothing kept, LACT turned it off, the state file says on: on", ko.person_choice("amdgpu_dpm", False), (True, "state file"))
kept({"amdgpu_dpm": False})
check("kept off: off, whatever the state file says", ko.person_choice("amdgpu_dpm", True), (False, "kept"))
kept(None)
ko.write_json(ko.OLD_RECORD, {"amdgpu_dpm": True})
state_file("false")
check("0.1.0's record: the person's choice", ko.person_choice("amdgpu_dpm", False), (True, "kept"))
ko.keep_person_choice("amdgpu_dpm", True)
check("kept once: 0.1.0's record is gone, the new file has it", (os.path.exists(ko.OLD_RECORD), ko.read_json(ko.PERSON)),
      (False, {"amdgpu_dpm": True}))
check("keeping the same choice again changes nothing", ko.keep_person_choice("amdgpu_dpm", True), False)


# who a change is taken from (Watch.action_call), with a stand-in bus and callers
class FakeBus:
    def __init__(self):
        self.live = {"amdgpu_dpm": True}

    def ppd_action(self, action):
        return self.live.get(action)


def watch(caller, lact_start=False):
    w = ko.Watch.__new__(ko.Watch)
    w.bus = FakeBus()
    w.expected = {}
    w.caller = lambda sender: caller
    w.lactd_just_started = lambda: lact_start
    w.changed = lambda *a: None
    return w


kept({"amdgpu_dpm": True})
watch("lact").action_call(":1.9", "amdgpu_dpm", False, 0)
check("LACT turns it off at its start: the person's choice stays on", ko.read_json(ko.PERSON), {"amdgpu_dpm": True})
watch("us").action_call(":1.2", "amdgpu_dpm", False, 0)
check("this service turns it off while a card is held: the person's choice stays on", ko.read_json(ko.PERSON), {"amdgpu_dpm": True})
watch("person").action_call(":1.40", "amdgpu_dpm", False, 0)
check("the person turns it off: kept off", ko.read_json(ko.PERSON), {"amdgpu_dpm": False})
watch("person").action_call(":1.41", "amdgpu_dpm", True, 0)
check("the person turns it on (during a hold too): kept on", ko.read_json(ko.PERSON), {"amdgpu_dpm": True})
watch(None, lact_start=True).action_call(":1.42", "amdgpu_dpm", False, 0)
check("a caller already gone, off, lactd just started: LACT's", ko.read_json(ko.PERSON), {"amdgpu_dpm": True})
watch(None, lact_start=False).action_call(":1.43", "amdgpu_dpm", False, 0)
check("a caller already gone, off, lactd not starting: the person's", ko.read_json(ko.PERSON), {"amdgpu_dpm": False})
watch(None, lact_start=True).action_call(":1.44", "amdgpu_dpm", True, 0)
check("a caller already gone, on: the person's (LACT only turns it off)", ko.read_json(ko.PERSON), {"amdgpu_dpm": True})
watch("person").action_call(":1.45", "trickle_charge", False, 0)
check("an action this service does not set: nothing kept", ko.read_json(ko.PERSON), {"amdgpu_dpm": True})

# without the monitor: a change this service did not make
w = watch(None, lact_start=True)
w.expected = {"amdgpu_dpm": True}
w.bus.live = {"amdgpu_dpm": False}
w.unmonitored_changes()
check("no monitor, off while lactd starts: LACT's", ko.read_json(ko.PERSON), {"amdgpu_dpm": True})
w = watch(None, lact_start=False)
w.expected = {"amdgpu_dpm": True}
w.bus.live = {"amdgpu_dpm": False}
w.unmonitored_changes()
check("no monitor, off at another time: the person's", ko.read_json(ko.PERSON), {"amdgpu_dpm": False})
w = watch(None)
w.expected = {}
w.bus.live = {"amdgpu_dpm": True}
w.unmonitored_changes()
check("no monitor, nothing seen yet: nothing taken", ko.read_json(ko.PERSON), {"amdgpu_dpm": False})
print("%d failed" % failed)
sys.exit(1 if failed else 0)
