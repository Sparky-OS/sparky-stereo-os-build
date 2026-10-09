#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""verify-fragment.py FINAL.config FRAGMENT.config...  -> PASS/FAIL per requested symbol; exit status 1 if any does not hold.

Used by kernel/configure.sh: the fragments say what the edition's kernel must have; the .config that make olddefconfig
produced from Debian's base must hold every one of those values (a dependency that is not met silently drops an option)."""
import re, sys

def load(path):
    d = {}
    for l in open(path, errors="replace"):
        l = l.rstrip("\n")
        m = re.match(r"^CONFIG_([A-Za-z0-9_]+)=(.*)$", l)
        if m:
            d[m.group(1)] = m.group(2); continue
        m = re.match(r"^# CONFIG_([A-Za-z0-9_]+) is not set$", l)
        if m:
            d[m.group(1)] = "n"
    return d

final = load(sys.argv[1])
want = {}
for f in sys.argv[2:]:
    want.update(load(f))
bad = 0
for k, v in want.items():
    got = final.get(k, "(absent)")
    if got != v:
        bad += 1
        print("FAIL CONFIG_%s: wanted %s, final %s" % (k, v, got))
print("# %d of %d requested values hold in the final .config" % (len(want) - bad, len(want)))
sys.exit(1 if bad else 0)
