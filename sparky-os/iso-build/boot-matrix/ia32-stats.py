#!/usr/bin/env python3
"""ia32-stats.py : count passes and black screens of every 32-bit UEFI run, per ISO and medium."""
import glob, os, sys
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "matrix-table.py")).read().split('if __name__')[0]
ns = {"__file__": os.path.join(os.path.dirname(os.path.abspath(__file__)), "matrix-table.py")}
exec(compile(src, "matrix-table.py", "exec"), ns)
run = ns["run"]
GROUPS = [
 ("as shipped, CD",  ["runs/sparky-asis/ia32-cd", "runs/sparky-asis-firstpass/ia32-cd"] + sorted(glob.glob("runs/ia32-repeat/asis-cd-*/"))),
 ("as shipped, USB", ["runs/sparky-asis/ia32-usb", "runs/sparky-asis-firstpass/ia32-usb"]),
 ("V1 new boot files, Sparky layout, CD",  ["runs/v1-new-sparky/ia32-cd"] + sorted(glob.glob("runs/ia32-repeat/v1-cd-*/")) + sorted(glob.glob("runs/v1-repeat/ia32-cd*/"))),
 ("V1, USB", ["runs/v1-new-sparky/ia32-usb"]),
 ("V2 new boot files, live-build layout, CD", ["runs/v2-new-debian/ia32-cd"]),
 ("V2, USB", ["runs/v2-new-debian/ia32-usb"] + sorted(glob.glob("runs/v2-repeat/ia32-usb-*/"))),
 ("V1 with a serial console on the kernel line, CD", sorted(glob.glob("runs/v1s-ia32/cd-*/"))),
 ("as shipped, CD, with CPU-state capture at 120 s and 150 s", sorted(glob.glob("runs/ia32-hmp/cd-*/"))),
]
print("| ISO and medium | runs | reached the desktop | black screen after the menu (no splash ever) | slow (splash seen, no desktop yet) | other |")
print("|---|---|---|---|---|---|")
for name, paths in GROUPS:
    res = [run(p.rstrip("/")) for p in paths if os.path.isdir(p.rstrip("/"))]
    res = [r for r in res if r]
    ok = sum(1 for r in res if r[0] == "pass")
    black = sum(1 for r in res if r[0] == "fail" and r[2].startswith("black"))
    slow = sum(1 for r in res if r[0] == "fail" and r[2].startswith("slow"))
    other = len(res) - ok - black - slow
    print("| %s | %d | %d | %d | %d | %d |" % (name, len(res), ok, black, slow, other))
