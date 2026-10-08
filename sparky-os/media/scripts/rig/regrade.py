#!/usr/bin/env python3
# usage: regrade.py <prefix> [screenwidth]  -> analyse again and judge every run of the prefix, writes results-<prefix>.txt
import sys, glob, subprocess, re, os
pre = sys.argv[1]; sw = sys.argv[2] if len(sys.argv) > 2 else '1280'
exp = [(r'-cat-3d2d-(mp4|mkv)$', '3d>2d@75'), (r'-cat-2d3d-mp4$', '2d>3d@75'), (r'-cat-sbs-tb-mp4$', '3d>3d@75'), (r'-cancel-60-mp4$', '3d>2d@60'), (r'-hevc-cat-3d2d-mp4$', '3d>2d@75'),
       (r'-(ord-2d|hevc-2d)-mp4$', '2d')]
lines = []
for d in sorted(glob.glob('runs/%s-*' % pre)):
    if not os.path.exists(d + '/caps.json') or d.startswith('runs/%s-egl-' % pre): continue
    subprocess.run(['python3', 'scripts/analyze.py', d, sw], capture_output=True)
    e = '3d'
    for pat, v in exp:
        if re.search(pat, d): e = v; break
    judge = 'scripts/judge_step.py' if '>' in e else 'scripts/judge.py'
    r = subprocess.run(['python3', judge, d, e], capture_output=True, text=True)
    lines.append(r.stdout.strip() or ('FAIL %s | judge error %s' % (d, r.stderr[-200:])))
open('results-%s.txt' % pre, 'w').write('\n'.join(lines) + '\n')
print(pre, sum(l.startswith('PASS') for l in lines), 'PASS', sum(l.startswith('FAIL') for l in lines), 'FAIL')
