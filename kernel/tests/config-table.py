#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""config-table.py FLAVOUR CFGDIR DEBIANCFG FRAG... -> prints a table of the fragment's options, and the side effects

For every option of the fragment(s): reason (the comment line(s) above it), value requested, value in Debian's own config,
value after Debian + olddefconfig on the patched tree (deb-only), value in the final .config, and HOLDS / NOT HOLDING.
Then lists the options whose final value differs from deb-only without being named in a fragment (side effects of
dependencies / selects), and the ones that Debian had and are gone from the tree."""
import re, sys
flavour, cfgdir, debcfg = sys.argv[1], sys.argv[2], sys.argv[3]
frags = sys.argv[4:]

def load(p):
    d = {}
    for l in open(p, errors='replace'):
        l = l.rstrip('\n')
        m = re.match(r'^CONFIG_([A-Za-z0-9_]+)=(.*)$', l)
        if m: d[m.group(1)] = m.group(2); continue
        m = re.match(r'^# CONFIG_([A-Za-z0-9_]+) is not set$', l)
        if m: d[m.group(1)] = 'n'
    return d

deb = load(debcfg)
only = load(cfgdir + '/deb-only/.config')
final = load(cfgdir + '/.config')

rows = []
named = set()
for fp in frags:
    reason = []
    hdr = 0          # 0 normal; 1 after a rule line (a section title follows); 2 after the title (the closing rule follows)
    for l in open(fp):
        l = l.rstrip('\n')
        if l.startswith('# ===='):
            hdr = 1 if hdr == 0 else 0
            reason = []
            continue
        if hdr == 1 and l.startswith('#'):
            hdr = 2
            continue
        m = re.match(r'^CONFIG_([A-Za-z0-9_]+)=(.*)$', l)
        m2 = re.match(r'^# CONFIG_([A-Za-z0-9_]+) is not set$', l)
        if m or m2:
            sym, want = (m.group(1), m.group(2)) if m else (m2.group(1), 'n')
            named.add(sym)
            rows.append((sym, want, ' '.join(reason).strip(), fp.split('/')[-1]))
            reason = []
        elif l.startswith('#') and not l.startswith('# ====') and l.strip('# ').strip():
            reason.append(l.lstrip('# ').strip())
        elif not l.strip():
            reason = []

bad = 0
print('%-34s %-8s %-8s %-8s %-8s %s' % ('option', 'wanted', 'debian', 'deb+old', 'final', 'verdict | reason'))
for sym, want, reason, src in rows:
    d, o, f = deb.get(sym, '-'), only.get(sym, '-'), final.get(sym, '-')
    holds = (f == want)
    kind = 'pin' if (d == want) else ('NEW' if d == '-' else 'DEVIATES')
    if not holds: bad += 1
    print('%-34s %-8s %-8s %-8s %-8s %s | %s' % (sym, want[:8], d[:8], o[:8], f[:8], ('HOLDS ' + kind) if holds else 'NOT HOLDING', reason[:150]))
print('# %d fragment options, %d not holding' % (len(rows), bad))

side = [(s, only.get(s, '-'), final.get(s, '-')) for s in sorted(set(only) | set(final)) if s not in named and only.get(s, '-') != final.get(s, '-')]
print('\n# side effects: %d options differ between deb+olddefconfig and final without being named in the fragment' % len(side))
for s, a, b in side[:200]:
    print('  %-40s %-8s -> %s' % (s, a[:8], b[:8]))
gone = [s for s in sorted(deb) if s not in only and deb[s] not in ('n',)]
print('\n# Debian options (set, not "n") that do not exist in the patched tree: %d' % len(gone))
print('  ' + ' '.join(gone[:80]))
sys.exit(1 if bad else 0)
