#!/usr/bin/python3 -I
"""eyeorder_judge.py RESULTS TAG...: judges the eye order steps (rig/guest/eyeorder-steps.sh) and the bench's analyze-eyeorder.py
over their frames. A tag holds when its mode was listed, set with the output's swap eyes off and on, and both frames equal the
packing's model built from the 2D reference (the left view first with the swap off, the right view first with the swap on) within
2 codes, with the other swap's model matching none of the pixels where the eyes differ (the negative control). The row holds when
every tag named holds (a tag ending in -right holds when the mode list has no right eye first twin: KWin lists none, the swap is the output's), the reference frame is the declared client's left view, the plain 2D output shows the left view (and the
right view with the swap on), right eye first twins equal the left eye first mode with the swap flipped, and the analysis ended
with 0 failed. Exit 0 holds, 1 does not, 77 the guest did not run to the end, 2 a crash."""
import os
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash
import re

lines = [l.strip() for l in open(sys.argv[1], errors="replace") if l.startswith("STEREO|")]
tags = [t for t in sys.argv[2:] if t != "plain"]
if not any(l.startswith("STEREO|eyeorder|kwin exit") for l in lines):
    print("SKIP: the eye order steps wrote no 'kwin exit' line (the guest or the compositor did not start): %s" % "; ".join(lines[-3:]))
    sys.exit(77)
checks = {}
for l in lines:
    m = re.match(r"STEREO\|check\|eyeorder/([^|]+)\|(PASS|FAIL)\|(.*)", l)
    if m:
        checks[m.group(1)] = (m.group(2) == "PASS", m.group(3))
summary = [l for l in lines if l.startswith("STEREO|summary|eyeorder|")]
ok = True
ref = checks.get("ref")
print("%-26s %s" % ("reference (2D mode)", ("holds: " + ref[1]) if ref and ref[0] else "does not hold: %s" % (ref[1] if ref else "no reference frame (the declared client was not shown)")))
ok = ok and bool(ref and ref[0])
for t in ["plain"] + tags:
    if t.endswith("-right"):
        # KWin lists no right eye first twin (stereo3d48: the eye order lives in the output's swap eyes setting), so the matrix's
        # "-right" tags hold when the mode list has none
        c = checks.get("%s is not listed" % t)
        print("%-26s %s: %s" % (t, "holds" if c and c[0] else "does not hold", (c[1] if c else "a right eye first twin is listed, or the mode list was not read")[:150]))
        ok = ok and bool(c and c[0])
        continue
    for sw in ("off", "on"):
        name = "%s swap %s" % (t, sw)
        if t == "plain":
            name = "plain 2D swap %s shows the %s view" % (sw, "right" if sw == "on" else "left")
        c = checks.get(name)
        verdict = "holds" if c and c[0] else "does not hold"
        print("%-26s %s: %s" % (name, verdict, (c[1] if c else "never set or never grabbed")[:150]))
        ok = ok and bool(c and c[0])
for name, c in sorted(checks.items()):
    if "right-first" in name or name.startswith("back to 2D"):
        if not c[0]:
            print("%-26s does not hold: %s" % (name, c[1]))
            ok = False
if not summary:
    print("the analysis wrote no summary")
    ok = False
else:
    failed = int(re.search(r"(\d+) failed", summary[0]).group(1))
    print("analysis: %s" % summary[0].split("|", 3)[3])
    ok = ok and failed == 0
sys.exit(0 if ok else 1)
