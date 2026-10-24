#!/usr/bin/env python3
"""summary.py RUNDIR... : re-classify each boot from its serial log (the rule of boots.py) and print one line per run:
counts, and for faults whether every trampoline was above 4 GiB and every RIP its address truncated to 32 bits."""
import json, os, sys, collections
for d in sys.argv[1:]:
    rows = [json.loads(l) for l in open(os.path.join(d, 'results.jsonl'))]
    c = collections.Counter()
    checks = collections.Counter()
    for r in rows:
        t = open(os.path.join(d, 'boot-%03d.serial' % r['boot']), errors='replace').read()
        if 'EFI246-OK' in t or ('EFI246 runtime=' in t and 'reboot: Power down' in t):
            res = 'pass'
        elif 'kernel tried to execute NX-protected page' in t:
            res = 'nxfault'
        elif 'Kernel panic' in t or 'Oops:' in t:
            res = 'oops'
        else:
            res = 'hang'
        c[res] += 1
        if 'tramp_pa' in r:
            hi = int(r['tramp_pa'], 16) >= 1 << 32
            checks[(res, 'tramp above 4G' if hi else 'tramp below 4G')] += 1
            if res == 'nxfault' and 'rip' in r:
                checks[('rip == (tramp+9) mod 4G', int(r['rip'], 16) == (int(r['tramp_pa'], 16) + 9) & 0xffffffff)] += 1
    print(os.path.basename(d.rstrip('/')), dict(c), dict(checks))
