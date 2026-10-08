#!/usr/bin/env python3
# usage: judge_step.py <rundir> <first>><second>@N     (frame by frame run: seek, then single steps, a capture after each)
# 3d>2d@N: the captures of frames < N are two views with equal numbers, frame N and the later ones are one view; 2d>3d@N the reverse;
# 3d>3d@N: all two views.  After a cancel the content is still the packed pair, so a flat capture has no readable number there:
# the change is then the first flat capture after the last two-view capture, which must be the capture after frame N-1.
import sys, json
d, exp = sys.argv[1], sys.argv[2]
a = json.load(open(d + '/analysis.json')); kind, n = exp.split('@'); n = int(n); first, second = kind.split('>')
caps = a['captures']
st = lambda c: c['kind'] == 'stereo' and c['frames'][0] == c['frames'][1] and c['colours'] == ['red', 'blue']
mono = lambda c: c['kind'] == 'mono'
ok = True; msgs = []
def fail(m):
    global ok; ok = False; msgs.append('FAIL ' + m)
seq = ''.join('S' if st(c) else 'M' if mono(c) else '?' for c in caps)
idx = [c['frames'][0] for c in caps]
msgs.append('captures %s' % seq)
if '?' in seq: fail('a capture is neither one view nor two equal views')
if first == '3d' and second == '2d':
    k = seq.find('M')
    if k < 1 or 'S' in seq[k:]: fail('not 3D then 2D: ' + seq)
    else:
        fr = idx[k - 1]
        msgs.append('last two-view capture frame %d; the first flat capture is the next one (frame %s, change at %d)' % (fr, idx[k] if caps[k]['colours'] == ['grey'] else 'unreadable', n))
        if fr != n - 1: fail('last 3D frame is %d, expected %d' % (fr, n - 1))
        if caps[k]['colours'] == ['grey'] and idx[k] != n: fail('first 2D frame is %d, expected %d' % (idx[k], n))
elif first == '2d' and second == '3d':
    k = seq.find('S')
    if k < 1 or 'M' in seq[k:]: fail('not 2D then 3D: ' + seq)
    else:
        msgs.append('last flat frame %d, first two-view frame %d (change at %d)' % (idx[k - 1], idx[k], n))
        if idx[k] != n or idx[k - 1] != n - 1: fail('change at %d, expected %d' % (idx[k], n))
else:
    if seq.strip('S'): fail('not two views throughout: ' + seq)
    fr = [c['frames'][0] for c in caps]
    if fr != list(range(fr[0], fr[0] + len(fr))): fail('frame numbers not consecutive: %s' % fr)
    if not (fr[0] < n <= fr[-1]): fail('the captures do not cross frame %d' % n)
    msgs.append('frames %d..%d, both sides of %d' % (fr[0], fr[-1], n))
# one declaration, removed once for 3d>2d, never for the others
a2 = a
if first == '3d' and second == '2d':
    if a['creates'] != 1 or a['destroys'] < 1: fail('declaration requests: creates=%d destroys=%d' % (a['creates'], a['destroys']))
else:
    if a['creates'] > 1 or a['destroys_before_end'] != 0: fail('declaration requests: creates=%d destroys_before_end=%d' % (a['creates'], a['destroys_before_end']))
print(('PASS ' if ok else 'FAIL ') + d.split('/')[-1] + ' | ' + ' | '.join(msgs))
sys.exit(0 if ok else 1)
