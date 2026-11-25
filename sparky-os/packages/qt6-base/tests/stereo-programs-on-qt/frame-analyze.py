#!/usr/bin/env python3
# frame-analyze.py CASE [MARGINS] -- row 863 part A4: for every capture of frame-case.sh, do Qt's frame and the window's
# content agree? On the virtual output the desktop is black, so the window's extent is the bounding box of the pixels
# that are not black; the content's extent is the bounding box of frame-check's magenta border. With Qt's own frame
# (margins left, top, right, bottom; default 3,30,3,3, the frame's margins the probe reads in the program rows) they
# agree when the content's box is the window's box inset by the margins, and the border is whole along each edge.
# The left eye is read when the capture is a pair. Prints one JSON object; "agree" is true when every step agrees.
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def bbox(mask):
    ys, xs = np.nonzero(mask)
    return [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None


def main():
    case = Path(sys.argv[1])
    ml, mt, mr, mb = (int(v) for v in (sys.argv[2] if len(sys.argv) > 2 else '3,30,3,3').split(','))
    steps = []
    for png in sorted(case.glob('step-*.png'), key=lambda p: int(p.stem.split('-')[1])):
        meta = json.loads(png.with_suffix('.json').read_text())
        a = np.asarray(Image.open(png).convert('RGB')).astype(int)
        if meta.get('stereo'):
            a = a[:, : a.shape[1] // 2]
        win = bbox(a.sum(axis=2) > 0)
        mag = (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)
        con = bbox(mag)
        row = {'step': int(png.stem.split('-')[1]), 'stereo': meta.get('stereo'), 'window': win, 'content': con,
               'paint': png.with_suffix('.paint').read_text().strip() if png.with_suffix('.paint').exists() else None}
        try:
            ws = json.loads(png.with_name(png.stem + '.windows.json').read_text())['windows']
            row['kwin_frame'] = [w['fg'] for w in ws if w.get('caption') == 'frame-check'][0]
        except (OSError, ValueError, KeyError, IndexError):
            row['kwin_frame'] = None
        if win and con:
            want = [win[0] + ml, win[1] + mt, win[2] - mr, win[3] - mb]
            row['content_expected'] = want
            x0, y0, x1, y1 = con
            whole = (mag[y0:y0 + 2, x0:x1 + 1].all() and mag[y1 - 1:y1 + 1, x0:x1 + 1].all()
                     and mag[y0:y1 + 1, x0:x0 + 2].all() and mag[y0:y1 + 1, x1 - 1:x1 + 1].all())
            row['border_whole'] = bool(whole)
            row['agree'] = con == want and bool(whole)
            row['off_by'] = [con[i] - want[i] for i in range(4)]
        else:
            row['agree'] = False
        steps.append(row)
    print(json.dumps({'case': case.name, 'margins': [ml, mt, mr, mb], 'steps': steps,
                      'agree': bool(steps) and all(s['agree'] for s in steps),
                      'disagreeing_steps': [s['step'] for s in steps if not s['agree']]}))


if __name__ == '__main__':
    main()
