#!/usr/bin/python3 -I
"""input_judge.py CONSOLE_LOG: judges the guest's LAB lines. The expectations are the HID report descriptor's own (rig/guest/
hidtest.c): usages 1 to 128 are buttons, 8 axes. A button count is the kernel's (EVIOCGBTNCNT where the kernel has EV_BTN, else
the key codes it sets) and SDL's. The hats are printed and are not a condition: hid-input maps every HID hat switch onto
ABS_HAT0X/Y on any kernel.
Exit 0 holds (everything seen whole), 1 does not, 77 the guest did not run."""
import os
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash

import re
import sys

lines = [l.strip() for l in open(sys.argv[1], errors="replace") if "LAB|" in l]
if not any("|guest|done" in l for l in lines):
    print("SKIP: the guest did not run to its end (see console.log)")
    sys.exit(77)
d = {}
for l in lines:
    f = l[l.index("LAB|"):].split("|")
    if len(f) > 3 and f[1] in ("hid", "sdl"):
        d[f[1]] = dict(x.split("=", 1) for x in f[3:] if "=" in x) if f[1] == "hid" else dict(x.split("=", 1) for x in f[3:] if "=" in x)
    if "error" in f[1:3]:
        print("guest error:", l)
want = {"buttons": 128, "axes": 8, "pressed": 128}
ok = True
for who in ("hid", "sdl"):
    if who not in d:
        print("%s: no answer" % ("kernel" if who == "hid" else "SDL"))
        ok = False
        continue
    row = d[who]
    for k, v in want.items():
        got = int(row.get(k, -1))
        flag = "ok" if got == v else "LOST %d" % (v - got) if got >= 0 else "missing"
        print("%-6s %-8s expected %3d got %3d  %s" % ("kernel" if who == "hid" else "SDL", k, v, got, flag))
        ok = ok and got == v
    print("%-6s hat codes or hats (not a condition) %s" % ("kernel" if who == "hid" else "SDL", row.get("hat_codes") or row.get("hats")))
print("kernel detail:", {k: v for k, v in d.get("hid", {}).items() if k in ("ev_btn_type", "btncnt_ioctl", "key_codes", "abs_codes")})
sys.exit(0 if ok else 1)
