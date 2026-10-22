#!/usr/bin/env python3
# Summarises the rig results of one prefix family (e.g. o3): per output, the number of clips that passed, counting a clip as passed
# when its first run passed or its serial rerun passed; lists every run that needed a rerun, with the reason.
import re, sys, os, glob
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'config'))
import local_config
# the rig's results, in the media-on-dmo work area of SPARKY_WORKSPACES
R = os.path.join(local_config.get('SPARKY_WORKSPACES'), 'media-on-dmo/work/rig')
pre = sys.argv[1]
def lines(p):
    return [l.rstrip('\n') for l in open(p)] if os.path.exists(p) else []
def clip(name, base):
    return name[len(base) + 1:]
for tag in ('dmabuf', 'gn', 'gpu', 'egl-gn', 'egl-gpu'):
    base = '%s-%s' % (pre, tag)
    first = {}; rerun = {}
    for l in lines('%s/results-%s.txt' % (R, base)):
        m = re.match(r'(PASS|FAIL) (\S+)', l)
        if m: first[clip(m.group(2), base)] = (m.group(1), l)
    for l in lines('%s/results-%s-retry.txt' % (R, base)):
        m = re.match(r'(PASS|FAIL) (\S+)', l)
        if m: rerun[clip(m.group(2), base + '-retry')] = (m.group(1), l)
    runs = sorted(os.path.basename(d)[len(base) + 1:] for d in glob.glob('%s/runs/%s-*' % (R, base)) if not os.path.basename(d).startswith(base + '-retry-'))
    allclips = sorted(set(runs))
    ok = 0; notes = []
    for c in allclips:
        f = first.get(c); r = rerun.get(c)
        if f and f[0] == 'PASS': ok += 1
        elif r and r[0] == 'PASS':
            ok += 1; notes.append('%s: first run %s, rerun PASS' % (c, 'FAILED (judge)' if f else 'lost by the harness (no capture)'))
        else: notes.append('%s: NOT PASSED (%s)' % (c, (f or r or ('-', 'no result'))[1][:150]))
    print('%-22s %d of %d clips pass' % (base, ok, len(allclips)))
    for n in notes: print('    ' + n)
