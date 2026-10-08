#!/usr/bin/env python3
# The FFmpeg checks of the stereo series, one build at a time (run inside a container whose ffmpeg/ffprobe is under test).
# For each clip of the rig (/clips), ffprobe's per-frame Stereo 3D side data, with one and with four decoder threads:
#   the clip's arrangement must be on EXACTLY the frames the stream says it applies to (SEI on keyframes only, HEVC, Matroska),
#   with the right type and eye order. Prints PASS/FAIL per clip and a summary; the same script runs on dmo's unpatched build.
import json, subprocess, sys, os
CL = sys.argv[1] if len(sys.argv) > 1 else '/clips'
import re
RE_FRAME = re.compile(r'\] n:\s*(\d+) ')
RE_SD = re.compile(r'side data - Stereo 3D: type - ([a-z ]+?)( \(inverted\))?, view')
def probe(path, threads):
    # showinfo prints, for every frame that comes out of the decoder, its Stereo 3D side data (type, eye order)
    r = subprocess.run(['ffmpeg', '-nostats', '-v', 'info', '-threads', str(threads), '-i', path, '-an', '-vf', 'showinfo', '-f', 'null', '-'], capture_output=True, text=True)
    if r.returncode: return None, (r.stderr.strip().splitlines() or [''])[-1][:200]
    out = []
    for line in r.stderr.splitlines():
        if RE_FRAME.search(line): out.append([])
        else:
            m = RE_SD.search(line)
            if m and out: out[-1].append((m.group(1), 1 if m.group(2) else 0))
    # one Stereo 3D entry per frame at most is what the series must leave; more than one shows as count > 1
    return [None if not e else (e[0][0], e[0][1], len(e)) for e in out], ''
def decode_ok(path):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'null', '-'], capture_output=True, text=True)
    return r.returncode, r.stderr.strip().splitlines()[-1][:120] if r.stderr.strip() else ''
# name -> (before, after, change): the arrangement (type, inverted) or None on the frames before and after source frame `change`
# (change 0 = the whole clip is one arrangement). SEI-only clips: the type comes from the stream; mkvmode-*: Matroska StereoMode only.
SBS, TB = 'side by side', 'top and bottom'
spec = {}
def whole(name, t, inv): spec[name] = ((t, inv) if t else None, (t, inv) if t else None, 0)
for k, t in (('sbs', SBS), ('tb', TB)):
    for e, inv in (('L', 0), ('R', 1)):
        for g in ('g12', 'g250'):
            for c in ('mp4', 'mkv'):
                whole('ord-%s-%s-%s.%s' % (k, e, g, c), t, inv)
for n, t, inv in (('hevc-sbs-L-g12.mp4', SBS, 0), ('hevc-sbs-L-g250.mkv', SBS, 0), ('hevc-sbs-R-g250.mkv', SBS, 1), ('hevc-tb-L-g12.mp4', TB, 0),
                  ('hevc-tb-L-g250.mp4', TB, 0), ('hevc-tb-R-g12.mkv', TB, 1), ('sei-every-sbs-L.mp4', SBS, 0), ('sei-every-tb-R.mp4', TB, 1),
                  ('x264-sbs-L-g12.mp4', SBS, 0), ('x265-sbs-L-g12.mp4', SBS, 0), ('x265-sbs-L-g250.mkv', SBS, 0), ('x265-tb-L-g12.mkv', TB, 0),
                  ('x265-tb-L-g250.mp4', TB, 0), ('mkvmode-sbs-L.mkv', SBS, 0), ('mkvmode-tb-R.mkv', TB, 1)):
    whole(n, t, inv)
whole('ord-2d.mp4', None, 0); whole('hevc-2d.mp4', None, 0)
spec['cat-3d2d.mp4'] = ((SBS, 0), None, 75); spec['cat-3d2d.mkv'] = ((SBS, 0), None, 75)
spec['hevc-cat-3d2d.mp4'] = ((SBS, 0), None, 75); spec['x265-cat-3d2d.mp4'] = ((SBS, 0), None, 75)
spec['cat-2d3d.mp4'] = (None, (SBS, 0), 75); spec['cat-sbs-tb.mp4'] = ((SBS, 0), (TB, 0), 75)
spec['cancel-60.mp4'] = ((SBS, 0), None, 60)
fails = 0; total = 0
for name in sorted(spec):
    path = os.path.join(CL, name)
    if not os.path.exists(path): print('MISSING', name); continue
    before, after, n = spec[name]
    res = []
    for th in (1, 4):
        fr, err = probe(path, th)
        total += 1
        if fr is None: res.append('threads=%d probe failed: %s' % (th, err)); fails += 1; continue
        T = len(fr); hidden = (150 - T) if n else 0       # frames an MP4 edit list hides before the first shown frame
        cut = max(n - hidden, 0) if n else 0
        ok = True; why = ''
        for i, d in enumerate(fr):
            want = before if (not n or i < cut) else after
            exp = None if want is None else (want[0], want[1], 1)
            if d != exp:
                ok = False; why = 'frame %d/%d: got %s expected %s' % (i, T, d, exp); break
        n3 = sum(1 for d in fr if d); res.append('threads=%d %d/%d frames with Stereo 3D %s' % (th, n3, T, 'ok' if ok else 'WRONG (' + why + ')'))
        if not ok: fails += 1
    print(('PASS ' if all(' ok' in r for r in res) else 'FAIL ') + name + ' | ' + ' | '.join(res))
# a stream SEI together with a container StereoMode: the CLI must not abort (EEXIST), and every frame carries one Stereo 3D entry
p = os.path.join(CL, 'both-sei-and-stereomode.mkv')
if os.path.exists(p):
    rc, msg = decode_ok(p); fr, err = probe(p, 1); total += 1
    good = rc == 0 and fr is not None and all(d and d[2] == 1 for d in fr)
    fails += 0 if good else 1
    print(('PASS ' if good else 'FAIL ') + 'both-sei-and-stereomode.mkv | ffmpeg rc=%d %s | %s' % (rc, msg, ('%d frames, one Stereo 3D entry each' % len(fr)) if fr else 'ffprobe: ' + err))
print('SUMMARY checks=%d failed=%d' % (total, fails))
sys.exit(1 if fails else 0)
