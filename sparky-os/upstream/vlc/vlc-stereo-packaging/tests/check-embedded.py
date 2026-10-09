#!/usr/bin/python3
"""Check the private 1280x800 KWin embedded-player fixture captures.

Usage: check-embedded.py /path/to/evidence
The fixture starts with Qt's 600x420 window, then requests frame geometry
(100,80,900,620). SBS/TB clips contain red/blue eyes and green/yellow edge
markers. A stereo flag alone must not pass: cropped eye views fail too.
"""
import json
from pathlib import Path
import sys
from PIL import Image, ImageChops

out = Path(sys.argv[1])
results = {}
cases = [('1', (340,230,940,578)), ('resized', (100,138,1000,648))]
cases += [(name, (100,138,1000,648)) for name in
          ['sei-sbs-L.mp4', 'sei-sbs-R.mp4', 'sei-tb-L.mp4', 'sei-tb-R.mp4']]
for name, box in cases:
    image = Image.open(out / ('vlc-' + name + '.png')).convert('RGB')
    assert image.size == (2560,800), (name, 'missing stereo capture')
    left = image.crop((0,0,1280,800))
    right = image.crop((1280,0,2560,800))
    difference = ImageChops.difference(left, right)
    difference.paste(0, box)
    assert difference.getbbox() is None, (name, '2D controls differ between eyes')
    x0,y0,x1,y1 = box
    for eye in (left,right):
        green = eye.getpixel((x0+30,y1-30))
        yellow = eye.getpixel((x1-30,y1-30))
        assert green[1] > 100 and green[0] < 100, (name, 'left edge missing', green)
        assert yellow[0] > 150 and yellow[1] > 150 and yellow[2] < 100, (
            name, 'right edge missing', yellow)
    l = left.getpixel((x0+(x1-x0)//2, y0+(y1-y0)//2))
    r = right.getpixel((x0+(x1-x0)//2, y0+(y1-y0)//2))
    assert l[0] > 150 and l[2] < 100, (name, 'left eye is not red', l)
    assert r[2] > 150 and r[0] < 100, (name, 'right eye is not blue', r)
    results[name] = {'controls_differing_pixels': 0, 'complete_eye_edges': True,
                     'normalized_eye_order': True}
for name in ['stopped', 'x264-2d.mp4']:
    image = Image.open(out / ('vlc-' + name + '.png'))
    assert image.size == (1280,800), (name, 'stale stereo state')
    results[name] = {'stereo': False}
(out/'pixel-proof.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS: full eye views, ordinary controls, eye order, mono restoration')
