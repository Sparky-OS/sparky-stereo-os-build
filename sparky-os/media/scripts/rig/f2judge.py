#!/usr/bin/env python3
# usage: f2judge.py <prefix>   -> results-<prefix>.txt from runs/<prefix>-*/analysis.json
# A picture is centred when the margins to the window's edges differ by at most 2 px (centre error <= 1 px) in both eyes, both eyes
# show it the same size, and it is where --vo=dmabuf-wayland puts it (the reference; where a window is not painted, the only check
# on that VO is the equality of its two eyes and the frame numbers).
import sys, json, glob, os, re
pre = sys.argv[1]; out = []
runs = sorted(glob.glob('runs/%s-*/analysis.json' % pre))
def load(p): return json.load(open(p))['captures'][-1]
for p in runs:
    nm = p.split('/')[1]; case, tag = re.match(r'%s-(.*)-([a-z-]+)$' % re.escape(pre), nm).groups()
    # the case names contain dashes: the tag is the last of the known ones
    for t in ('gpu-egl', 'gn-egl', 'dmabuf', 'gpu', 'gn'):
        if nm.endswith('-' + t): tag = t; case = nm[len(pre) + 1:-len(t) - 1]; break
    c = load(p); pl = c['place']; rect = c['rect']
    if c['kind'] != 'stereo' or None in rect: out.append('FAIL %s | capture %s %s' % (nm, c['kind'], rect)); continue
    ok = c['frames'][0] == c['frames'][1] and rect[0][2:] == rect[1][2:]
    notes = []
    if all(pl): 
        err = max(abs(v) for q in pl for v in q['centre_err']); ok &= err <= 1.0
        notes.append('margins L%s R%s, centre error max %.1f px' % (pl[0]['margins'], pl[1]['margins'], err))
    else: notes.append('window not painted, no margins')
    refp = 'runs/%s-%s-dmabuf/analysis.json' % (pre, case)
    if tag != 'dmabuf' and os.path.exists(refp):
        r = load(refp)['rect']
        d = max(abs(a - b) for e in (0, 1) for a, b in zip(rect[e], r[e]))
        ok &= d <= 1; notes.append('against dmabuf-wayland: max difference %d px' % d)
    out.append('%s %s | pic L%s R%s | %s | frames %s' % ('PASS' if ok else 'FAIL', nm, tuple(rect[0]), tuple(rect[1]), '; '.join(notes), c['frames']))
open('results-%s.txt' % pre, 'w').write('\n'.join(out) + '\n')
print(sum(l.startswith('PASS') for l in out), 'PASS', sum(l.startswith('FAIL') for l in out), 'FAIL')
