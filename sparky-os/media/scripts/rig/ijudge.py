#!/usr/bin/env python3
# usage: ijudge.py <rundir> <3d|2d>   -> PASS/FAIL line from interp.json
import sys, json
d, kind = sys.argv[1], sys.argv[2]; o = json.load(open(d + '/interp.json'))
seq = []
ok = True; msgs = []; blended = 0; n = 0; worst = 0.0; massr = []
for c in o:
    e = c['eyes']
    if not all(e) or any(x['cx'] is None for x in e): continue
    n += 1
    fr = ((e[0]['cx'] - 59.5) / 20.0) % 1.0
    if 0.1 <= fr <= 0.9: blended += 1
    if kind == '3d':
        if c['kind'] != 'stereo': ok = False; msgs.append('capture %d not stereo' % c['i']); continue
        dx = abs(e[0]['cx'] - e[1]['cx']); worst = max(worst, dx)
        if dx > 1.5: ok = False; msgs.append('capture %d: left %.2f right %.2f' % (c['i'], e[0]['cx'], e[1]['cx']))
        massr.append(e[0]['mass'] / e[1]['mass'])
        if e[1]['red'] or e[0]['blue']: ok = False; msgs.append('capture %d: red pixels in the right eye %d, blue in the left %d' % (c['i'], e[1]['red'], e[0]['blue']))
    elif kind == '2d':
        if c['kind'] != 'mono': ok = False; msgs.append('capture %d not mono' % c['i'])
    else:     # a 3D file, a 2D file, a 3D file: stereo captures need equal eyes and no leak, mono ones are the 2D file
        if c['kind'] == 'stereo':
            dx = abs(e[0]['cx'] - e[1]['cx']); worst = max(worst, dx)
            if dx > 1.5: ok = False; msgs.append('capture %d: left %.2f right %.2f' % (c['i'], e[0]['cx'], e[1]['cx']))
            if e[1]['red'] or e[0]['blue']: ok = False; msgs.append('capture %d: red pixels in the right eye %d, blue in the left %d' % (c['i'], e[1]['red'], e[0]['blue']))
        else:
            if e[0]['red'] or e[0]['blue']: ok = False; msgs.append('capture %d: mono capture with red/blue %d/%d' % (c['i'], e[0]['red'], e[0]['blue']))
        seq.append(c['kind'][0])
if n == 0: ok = False; msgs.append('no capture shows the marker')
if massr and (max(massr) - min(massr)) / (sum(massr) / len(massr)) > 0.03: ok = False; msgs.append('mass ratio left/right varies %.3f..%.3f' % (min(massr), max(massr)))
if kind == 'change':
    t = ''.join(seq); import re
    if not re.fullmatch(r's+m+s+', t): ok = False; msgs.append('sequence %s is not 3D, 2D, 3D' % t)
    else: msgs.append('sequence %s' % t)
print('%s %s | %d captures, %d between source frames (blended marker), max |left - right| %.2f px%s' % ('PASS' if ok else 'FAIL', d.split('/')[-1], n, blended, worst, (' | ' + '; '.join(msgs[:4])) if msgs else ''))
