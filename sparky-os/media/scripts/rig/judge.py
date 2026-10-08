#!/usr/bin/env python3
# usage: judge.py <rundir> <expect>   expect: 3d | 2d | 3d>2d@N | 2d>3d@N | 3d>3d@N
# Decides from analysis.json (pixels and the Wayland log), never from the words in the pictures.
import sys, json
d, exp = sys.argv[1], sys.argv[2]
a = json.load(open(d + '/analysis.json'))
caps = [c for c in a['captures'] if c['frames'][0] is not None]     # captures that show the video
msgs = []; ok = True
def fail(m):
    global ok; ok = False; msgs.append('FAIL ' + m)
def stereo_ok(c):
    return c['kind'] == 'stereo' and len(c['frames']) == 2 and c['frames'][0] == c['frames'][1] and c['colours'] == ['red', 'blue']
kind, _, n = exp.partition('@'); n = int(n) if n else None
dec = a['decl_events']
if kind == '3d':
    bad = [c for c in caps if not stereo_ok(c)]
    if bad: fail('captures not two views with equal frame numbers: %s' % [(c['i'], c['t'], c['kind'], c['frames'], c['colours']) for c in bad[:5]])
    if a['creates'] != 1 or a['set_content'] != 1 or a['destroys_before_end'] != 0: fail('declaration requests: creates=%d set_content=%d destroys_before_end=%d' % (a['creates'], a['set_content'], a['destroys_before_end']))
    msgs.append('%d captures all stereo, frames %s..%s' % (len(caps), caps[0]['frames'][0], caps[-1]['frames'][0]))
elif kind == '2d':
    bad = [c for c in caps if c['kind'] != 'mono']
    if bad: fail('stereo capture of a 2D clip: %s' % [(c['i'], c['t']) for c in bad[:5]])
    if a['creates'] or a['set_content']: fail('2D clip declared: creates=%d set_content=%d' % (a['creates'], a['set_content']))
    msgs.append('%d captures all mono, no declaration' % len(caps))
else:
    first, second = kind.split('>')
    cut = n
    # captures show the number of the frame displayed; the first view's number decides which side of the change
    for c in caps:
        f = c['frames'][0]
        want = first if f < cut - 3 else second if f >= cut + 3 else None   # within 3 frames of the change either is fine
        if want is None: continue
        if want == '3d' and not stereo_ok(c): fail('frame %s expected 3D: %s %s %s' % (f, c['kind'], c['frames'], c['colours']))
        if want == '2d' and c['kind'] != 'mono': fail('frame %s expected 2D: %s' % (f, c['kind']))
    # nearest frames to the change
    before = [c for c in caps if c['frames'][0] < cut]; after = [c for c in caps if c['frames'][0] >= cut]
    if not before or not after: fail('no captures on both sides of frame %d' % cut)
    else:
        lb, fa = before[-1], after[0]
        msgs.append('last capture before: frame %s %s; first after: frame %s %s' % (lb['frames'][0], lb['kind'], fa['frames'][0], fa['kind']))
        if first == '3d' and second == '2d':
            if not stereo_ok(lb): fail('capture just before the change is not 3D')
            if fa['kind'] != 'mono': fail('capture just after the change is not 2D')
        if first == '2d' and second == '3d':
            if lb['kind'] != 'mono': fail('capture just before the change is not 2D')
            if not stereo_ok(fa): fail('capture just after the change is not 3D')
        if first == '3d' and second == '3d':
            if not (stereo_ok(lb) and stereo_ok(fa)): fail('not two views on both sides')
    t_c = dec[0][0] if dec else None
    if first == '3d' and second == '2d':
        dd = [e for e in dec if e[1] == 'destroy']
        if a['creates'] != 1 or len(dd) != 1: fail('declaration requests: creates=%d destroys=%d' % (a['creates'], len(dd)))
        else: msgs.append('declared at %.2f s, removed at %.2f s: %.1f frames at 25 fps after the first frame (change at frame %d)' % (t_c, dd[0][0], (dd[0][0] - t_c) * 25, cut))
    if first == '2d' and second == '3d':
        if a['creates'] != 1 or a['destroys_before_end'] != 0: fail('declaration requests: creates=%d destroys_before_end=%d' % (a['creates'], a['destroys_before_end']))
        else: msgs.append('declared at %.2f s' % t_c)
    if first == '3d' and second == '3d':
        if a['creates'] != 1 or a['destroys_before_end'] != 0: fail('declaration requests: creates=%d destroys_before_end=%d' % (a['creates'], a['destroys_before_end']))
print(('PASS ' if ok else 'FAIL ') + d.split('/')[-1] + ' | ' + ' | '.join(m for m in msgs))
sys.exit(0 if ok else 1)
