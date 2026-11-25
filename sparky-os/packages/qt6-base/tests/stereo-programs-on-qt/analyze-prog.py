#!/usr/bin/env python3
# analyze-prog.py CASE [CONTROL_CASE] -- row 863 part A: one program case of run-prog.sh, measured, as one JSON object.
# For each captured step (step-K.png, both eyes side by side, left eye first, when KWin says the screen holds stereo
# content, "stereo": true in step-K.json; one picture of the screen otherwise, which counts as no pair): the pixels where
# the eyes differ and their bounding box (a pair shows only where the stereo area is); the probe's line for the step (each watched widget's
# expected place, its window's place, placed); lag.py over the wire log (the parent's commits that showed a stereo window
# away from its widget). With CONTROL_CASE (the same program on the published Qt): for each step both have, the pixels
# of each eye that differ between the two runs and their bounding box.
# The first watched widget's rectangle on the screen is KWin's frame of the active window (step-K.windows.json: with Qt's
# own frame it is the whole surface) plus the probe's frame margins and the widget's place and size; "pair_inside" says
# whether every pixel where the eyes differ lies inside it. With --measure, the program's own proof measure runs on the
# window cut from both eyes (step-K.measure/window.png) and the shim's record (step-K.geom.txt):
#   kalgebra, kalzium:XYZ, kubrick  sparky-os/upstream/qtbase/glwidget/rig/an-ka.py, an-kz.py (molecule XYZ), an-kub.py
#                                   (separation 5, the rig's), the analyzers of the Qt rig that proved those programs
#   vlc                             sparky-os/upstream/vlc/vlc-stereo-packaging/tests/check-embedded.py's rule on
#                                   mkclips2.py's film (each eye's view 1280x720, red left and blue right, green and
#                                   yellow markers at its bottom corners): the picture fitted in the widget's rectangle,
#                                   in each eye its own colour and both markers, the eyes the same outside the widget;
#                                   sampled at fractions of the box (check-embedded.py's fixed 30 px inset misses the
#                                   markers of a small video)
#   fraqtive                        sparky-os/upstream/fraqtive/proof/measure.py's rule: the 3D view draws at least 1000
#                                   colours and 30 % non-black pixels, in each eye (here in the widget's rectangle)
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
# build main's sparky-os/upstream, or the copy of its few files a kit carries (R863_UPSTREAM)
RIG = Path(os.environ.get('R863_UPSTREAM') or HERE.parents[3] / 'upstream') / 'qtbase' / 'glwidget' / 'rig'
KEY = re.compile(r'(\w+)=(-?\d+)(?:[,x](-?\d+))?')


def probe_fields(line):
    return {m.group(1): (int(m.group(2)), int(m.group(3)) if m.group(3) is not None else None) for m in KEY.finditer(line or '')}


def active_frame(png):
    try:
        ws = json.loads(png.with_name(png.stem + '.windows.json').read_text())['windows']
    except (OSError, ValueError, KeyError):
        return None
    act = [w for w in ws if w.get('active') and not w.get('popup') and not w.get('tooltip')]
    return act[0]['fg'] if act else None


def program_measure(kind, png, L, R, frame, rect_in_window):
    mdir = png.with_name(png.stem + '.measure')
    mdir.mkdir(exist_ok=True)
    x, y, w, h = [int(round(v)) for v in frame]
    Image.fromarray(np.concatenate([L[y:y + h, x:x + w], R[y:y + h, x:x + w]], axis=1).astype(np.uint8)).save(mdir / 'window.png')
    geom = png.with_name(png.stem + '.geom.txt')
    out = {'kind': kind}
    if kind == 'vlc':
        rx, ry, rw, rh = rect_in_window
        sx, sy = x + rx, y + ry
        k = min(rw / 1280, rh / 720)
        bw, bh = 1280 * k, 720 * k
        x0, y0 = int(round(sx + (rw - bw) / 2)), int(round(sy + (rh - bh) / 2))
        x1, y1 = int(round(sx + (rw + bw) / 2)) - 1, int(round(sy + (rh + bh) / 2)) - 1
        out['box'] = [x0, y0, x1, y1]
        if x0 < 0 or y0 < 0 or x1 >= L.shape[1] or y1 >= L.shape[0]:
            # part of the video box is off the screen (a window larger than the screen): nothing to judge
            out['offscreen'] = True
            out['ok'] = None
            return out
        def px(a, xx, yy):
            return [int(v) for v in a[yy, xx]]
        ok = True
        for eye, a, want in (('left', L, 'red'), ('right', R, 'blue')):
            # at fractions of the box, so a small video (the playlist's panel) is read as a large one: the view's colour
            # half across and a fifth down (below the frame-number blocks, above the letters), the green and yellow
            # markers (an eighth of the width, a quarter of the height) a sixteenth in from the bottom corners
            bw_, bh_ = x1 - x0 + 1, y1 - y0 + 1
            c = px(a, x0 + bw_ // 2, y0 + int(0.2 * bh_))
            g = px(a, x0 + bw_ // 16, y0 + int(0.875 * bh_))
            ye = px(a, x1 - bw_ // 16, y0 + int(0.875 * bh_))
            out[eye] = {'centre': c, 'green_corner': g, 'yellow_corner': ye}
            colour = (c[0] > 150 and c[2] < 100) if want == 'red' else (c[2] > 150 and c[0] < 100)
            ok = ok and colour and g[1] > 100 and g[0] < 100 and ye[0] > 150 and ye[1] > 150 and ye[2] < 100
        outside = np.abs(L - R).sum(axis=2) > 0
        outside[sy:sy + rh, sx:sx + rw] = False
        out['differ_outside'] = int(outside.sum())
        out['ok'] = bool(ok and out['differ_outside'] == 0)
        return out
    if kind == 'fraqtive':
        rx, ry, rw, rh = rect_in_window
        for eye, a in (('left', L), ('right', R)):
            v = a[y + ry:y + ry + rh, x + rx:x + rx + rw].reshape(-1, 3).astype(int)
            k = (v[:, 0] << 16) | (v[:, 1] << 8) | v[:, 2]
            out[eye + '_colours'], out[eye + '_nonblack'] = int(len(np.unique(k))), round(float((k != 0).mean()), 4)
        out['ok'] = all(out[e + '_colours'] >= 1000 and out[e + '_nonblack'] >= 0.30 for e in ('left', 'right'))
        return out
    if not geom.exists():
        return dict(out, ok=False, error='no shim record for this capture')
    (mdir / 'geom.txt').write_bytes(geom.read_bytes())
    env = dict(os.environ)
    if kind == 'kalgebra':
        cmd = [str(RIG / 'an-ka.py'), str(mdir), '5']
    elif kind.startswith('kalzium:'):
        cmd = [str(RIG / 'an-kz.py'), str(mdir), kind.split(':', 1)[1]]
    else:
        cmd = [str(RIG / 'an-kub.py'), str(mdir), '5']
        env['OX'], env['OY'] = str(rect_in_window[0]), str(rect_in_window[1])
    r = subprocess.run([sys.executable, '-I'] + cmd, capture_output=True, text=True, env=env)
    text = r.stdout + r.stderr
    out['text'] = text.strip().splitlines()[-14:]
    m = re.search(r'median abs (?:error )?([0-9.]+)', text)
    out['median_abs_px'] = float(m.group(1)) if m else None
    m = re.search(r'(?:outside the 3D view|outside the molecule viewer|outside the cubes. silhouettes)[^:]*: (\d+)', text)
    out['differ_outside'] = int(m.group(1)) if m else None
    m = re.search(r'in the window: x (\d+)\.\.(\d+), y (\d+)\.\.(\d+)', text)
    if m:
        a, b, c, d = (int(v) for v in m.groups())
        out['view_rect'] = [a, c, b - a + 1, d - c + 1]
        out['view_rect_is_widget'] = out['view_rect'] == list(rect_in_window)
    out['ok'] = (r.returncode == 0 and out['median_abs_px'] is not None and out['median_abs_px'] <= 1.0
                 and out['differ_outside'] == 0 and out.get('view_rect_is_widget', True))
    return out


def stereo_capture(png):
    try:
        return bool(json.loads(png.with_suffix('.json').read_text()).get('stereo'))
    except (OSError, ValueError):
        return None


def eyes(png):
    a = np.asarray(Image.open(png).convert('RGB')).astype(np.int16)
    if not stereo_capture(png):
        return a, a
    w = a.shape[1] // 2
    return a[:, :w], a[:, w:]


def bbox(mask):
    ys, xs = np.nonzero(mask)
    return [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None


def steps(case):
    return sorted((int(p.stem.split('-')[1]), p) for p in case.glob('step-*.png'))


def main():
    args = sys.argv[1:]
    measure = None
    if '--measure' in args:
        i = args.index('--measure')
        measure = args[i + 1]
        del args[i:i + 2]
    case = Path(args[0])
    control = Path(args[1]) if len(args) > 1 else None
    stderr = (case / 'stderr.txt').read_text(errors='replace') if (case / 'stderr.txt').exists() else ''
    probe = {int(m.group(1)): m.group(0) for m in re.finditer(r'^R863 step=(\d+) .*$', stderr, re.M)}
    result = re.search(r'^R863 result .*$', stderr, re.M)
    out = {'case': case.name, 'steps': [], 'probe_result': result.group(0) if result else None}
    for k, png in steps(case):
        L, R = eyes(png)
        d = np.abs(L - R).sum(axis=2) > 0
        row = {'step': k, 'stereo_capture': stereo_capture(png), 'pair_px': int(d.sum()), 'pair_bbox': bbox(d), 'probe': probe.get(k)}
        f = probe_fields(probe.get(k))
        frame = active_frame(png)
        if frame and 'expect' in f and 'size' in f and 'margins' in f:
            rect_in_window = [f['margins'][0] + f['expect'][0], f['margins'][1] + f['expect'][1], f['size'][0], f['size'][1]]
            rect = [frame[0] + rect_in_window[0], frame[1] + rect_in_window[1], rect_in_window[2], rect_in_window[3]]
            row['frame'], row['widget_rect'], row['visible'] = frame, rect, f.get('visible', (None,))[0]
            b = row['pair_bbox']
            row['pair_inside'] = None if b is None else (rect[0] <= b[0] and rect[1] <= b[1] and b[2] < rect[0] + rect[2] and b[3] < rect[1] + rect[3])
            if measure and row['stereo_capture'] and row['visible']:
                row['measure'] = program_measure(measure, png, L, R, frame, rect_in_window)
        if control and (control / png.name).exists():
            cL, cR = eyes(control / png.name)
            if cL.shape == L.shape:
                dl = np.abs(L - cL).sum(axis=2) > 0
                dr = np.abs(R - cR).sum(axis=2) > 0
                row['vs_control_left_px'], row['vs_control_left_bbox'] = int(dl.sum()), bbox(dl)
                row['vs_control_right_px'], row['vs_control_right_bbox'] = int(dr.sum()), bbox(dr)
        out['steps'].append(row)
    if (case / 'stderr.txt').exists():
        lag = subprocess.run([sys.executable, '-I', str(HERE / 'lag.py'), str(case / 'stderr.txt')], capture_output=True, text=True)
        try:
            out['lag'] = json.loads(lag.stdout)
        except ValueError:
            out['lag'] = {'error': lag.stderr[-300:]}
    log = (case / 'case.log').read_text(errors='replace') if (case / 'case.log').exists() else ''
    m = re.search(r'program alive at the end: (\w+)', log)
    out['alive_at_end'] = m.group(1) if m else None
    out['maps'] = (case / 'maps.txt').read_text().splitlines()[:40] if (case / 'maps.txt').exists() else []
    print(json.dumps(out))


if __name__ == '__main__':
    main()
