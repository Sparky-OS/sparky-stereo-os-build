#!/usr/bin/python3 -I
"""screens_judge.py RESULTS LAYOUT...: judges the bench's kwin phase lines (STEREO|check|kwin/LAYOUT-KIND ...|PASS|FAIL).
A layout holds when its mode was listed and set (checks exist) and every check of it passed: the desktop identical in both
eyes, a fullscreen 2D client identical in both eyes, the declared client's left view only in the left eye and its right view
only in the right eye at the same place (a plain 2D mode: the left view only, one eye), the same client as a plain 2D one
the same in both eyes. A layout the compositor did not list has no checks and does not hold ("nothing").
Exit 0 every layout holds, 1 one does not, 77 the guest did not run to its summary."""
import os
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash

import re
import sys

lines = [l.strip() for l in open(sys.argv[1], errors="replace") if l.startswith("STEREO|")]
layouts = sys.argv[2:]
if not any(l.startswith("STEREO|summary|kwin|") for l in lines):
    why = [l for l in lines if "|FAIL|" in l or "|error|" in l][:3]
    print("SKIP: the kwin phase wrote no summary (the guest or the compositor did not start): %s" % "; ".join(why))
    sys.exit(77)
ok = True
for lay in layouts:
    if lay == "edid-no-3d":
        # the EDID the guest read (edid-decode, written beside the results) declares no HDMI 3D: no "3D present", no "3D:" structure line
        path = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), "..", "edid-decode.txt")
        text = open(path, errors="replace").read() if os.path.exists(path) else ""
        hdmi = "Vendor-Specific Data Block (HDMI)" in text
        threed = [l.strip() for l in text.splitlines() if re.search(r"\b3D present\b|^\s*3D:|3D VIC", l)]
        good = hdmi and not threed
        print("%-9s the EDID is an HDMI sink (a vendor block: %s) declaring no 3D (%d lines about 3D) -> %s" % (lay, "yes" if hdmi else "no", len(threed), "holds" if good else "does not hold"))
        ok = ok and good
        continue
    if lay == "no-3d-modes":
        # the compositor lists no 3D mode for that output (the count line of the kwin phase)
        n = [re.search(r"output \S+, (\d+) 3D modes listed", l) for l in lines if l.startswith("STEREO|kwin|output ")]
        n = [int(m.group(1)) for m in n if m]
        good = bool(n) and n[0] == 0
        print("%-9s the compositor lists %s 3D modes -> %s" % (lay, n[0] if n else "an unknown number of", "holds" if good else "does not hold"))
        ok = ok and good
        continue
    chk = [l for l in lines if re.match(r"STEREO\|check\|kwin/%s-" % re.escape(lay), l)]
    skip = [l for l in lines if l.startswith("STEREO|skip|kwin/%s|" % lay)]
    passed = [l for l in chk if "|PASS|" in l]
    failed = [l for l in chk if "|FAIL|" in l]
    if skip or not chk:
        print("%-9s mode not listed by the compositor: nothing to show" % lay)
        ok = False
        continue
    print("%-9s %d checks, %d passed, %d failed" % (lay, len(chk), len(passed), len(failed)))
    for l in failed[:4]:
        print("   ", l.split("|", 3)[2], l.split("|", 4)[-1][:160])
    ok = ok and not failed
sys.exit(0 if ok else 1)
