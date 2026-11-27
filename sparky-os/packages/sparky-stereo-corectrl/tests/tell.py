#!/usr/bin/python3
# What the person is told, and when a notice ends: each notice is kept once; a conflict's notice ends with the conflict;
# a holder's notice ends when its program, running, no longer holds it, or when it is removed. The problems engine is
# a stand-in that logs its arguments.
import importlib.machinery
import importlib.util
import os
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OWNER = os.environ.get("KNOB_OWNER", os.path.join(HERE, "..", "bin", "knob-owner"))
root = tempfile.mkdtemp(prefix="knob-tell-")
os.environ["SPARKY_KNOB_ROOT"] = root
os.makedirs(root + "/fixture")
stub = os.path.join(root, "bin")
os.makedirs(stub)
log = os.path.join(root, "engine.log")
with open(os.path.join(stub, "sparky-stereo-problems"), "w") as f:
    f.write('#!/bin/sh\necho "$*" >>%s\n' % log)
os.chmod(os.path.join(stub, "sparky-stereo-problems"), stat.S_IRWXU)
os.environ["PATH"] = stub + ":" + os.environ["PATH"]
loader = importlib.machinery.SourceFileLoader("knob_owner", OWNER)
ko = importlib.util.module_from_spec(importlib.util.spec_from_loader("knob_owner", loader))
loader.exec_module(ko)


def installed(program, present):
    path = root + ko.PROGRAMS[program]
    if present:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w").close()
    elif os.path.exists(path):
        os.unlink(path)


def calls(step):
    open(log, "w").close()
    step()
    return [line.strip() for line in open(log)]


failed = 0


def check(name, got, want):
    global failed
    ok = got == want
    failed += not ok
    print("%s  %s" % ("ok  " if ok else "FAIL", name))
    if not ok:
        print("      want %s\n      got  %s" % (want, got))


CPU = {"cpu": ["LOCAL2", "CoreCtrl"]}
BOTH = {"both-0000-03-00.0": ["LOCAL4", "CoreCtrl", "LACT", "card0 (PCI 0000:03:00.0)"]}
installed("CoreCtrl", True)
installed("LACT", True)
check("a new notice is kept once", calls(lambda: ko.tell(CPU)),
      ["keep --machine --severity notice sparky-stereo-corectrl cpu LOCAL2 CoreCtrl"])
check("the same notice again: nothing", calls(lambda: ko.tell(CPU)), [])
check("the holder closed, still installed: the notice stays", calls(lambda: ko.tell({})), [])
check("the holder runs and no longer holds (its settings changed): the notice ends", calls(lambda: ko.tell({}, ["CoreCtrl"])),
      ["clear --machine sparky-stereo-corectrl cpu"])
check("it holds again: told again", calls(lambda: ko.tell(CPU, ["CoreCtrl"])),
      ["keep --machine --severity notice sparky-stereo-corectrl cpu LOCAL2 CoreCtrl"])
MANUAL = {"manual-cpu-games": ["LOCAL13", "games"]}
check("a manual profile is told", calls(lambda: ko.tell(dict(CPU, **MANUAL), ["CoreCtrl"])),
      ["keep --machine --severity notice sparky-stereo-corectrl manual-cpu-games LOCAL13 games"])
check("the manual profile gone: its notice ends, the hold's stays", calls(lambda: ko.tell(CPU, ["CoreCtrl"])),
      ["clear --machine sparky-stereo-corectrl manual-cpu-games"])
check("a conflict is told", calls(lambda: ko.tell(dict(CPU, **BOTH))),
      ["keep --machine --severity notice sparky-stereo-corectrl both-0000-03-00.0 LOCAL4 CoreCtrl LACT card0 (PCI 0000:03:00.0)"])
check("the conflict ends: its notice ends", calls(lambda: ko.tell(CPU)), ["clear --machine sparky-stereo-corectrl both-0000-03-00.0"])
installed("CoreCtrl", False)
check("CoreCtrl removed: its notice ends", calls(lambda: ko.tell({})), ["clear --machine sparky-stereo-corectrl cpu"])
check("nothing left to forget", calls(lambda: ko.tell({})), [])
print("%d failed" % failed)
sys.exit(1 if failed else 0)
