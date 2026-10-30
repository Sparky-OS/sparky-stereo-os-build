#!/usr/bin/env python3
"""Check the D3D9 child/reparent probe against its analytic eyes and ordinary mono UI.

Inputs are result.json files and adjacent lossless captures from the isolated rig.
A clipped case requires a named Composite pixmap capture, because XGetImage on
its shaped window does not expose the complete source buffer.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('stereo_result', type=Path)
parser.add_argument('mono_reference', type=Path)
args = parser.parse_args()
root = args.stereo_result.parent
reference = args.mono_reference.parent
result = json.loads(args.stereo_result.read_text())
mono = json.loads(args.mono_reference.read_text())
assert result['returncode'] == mono['returncode'] == 0
assert len(result['phases']) == len(mono['phases']) == 2
text = (root / 'client.stdout').read_text()
assert ('clip_enabled=0' in text) != ('clip_enabled=1' in text)
clipped = 'clip_enabled=1' in text
atoms = json.loads((root / 'atoms.json').read_text())
wire = [json.loads(line) for line in (root / 'wire.jsonl').read_text().splitlines()]
content = [r for r in wire if r.get('atom') == atoms['_KDE_NET_WM_STEREO_CONTENT'] and r['opcode'] == 18]
assert len(content) == 1 and content[0]['value'] == [3]
child = content[0]['window']
assert any(r['opcode'] == 4 and r.get('window') == child for r in wire)
rows = []
for index, (phase, control) in enumerate(zip(result['phases'], mono['phases'])):
    width, height = phase['logical']
    assert [width, height] == ([320, 200] if index == 0 else [256, 160])
    title = 'D3D9 Owner ' + ('B' if index else 'A')
    owner = next(w for w in phase['all_windows'] if w['title'] == title)
    old_owner = next(w for w in control['all_windows'] if w['title'] == title)
    native = next(w for w in phase['windows'] if w.get('declaration'))
    assert native['id'] == child and native['parent'] == owner['id']
    assert owner['declaration'] is None
    assert owner['properties']['_KDE_NET_WM_STEREO_CONTENT_CHILDREN'] == [child]
    if index:
        previous = next(w for w in phase['all_windows'] if w['title'] == 'D3D9 Owner A')
        assert not previous['properties'].get('_KDE_NET_WM_STEREO_CONTENT_CHILDREN')
    screen = np.asarray(Image.open(root / f'phase{index}-screen.png').convert('RGB'))
    ordinary = np.asarray(Image.open(reference / f'phase{index}-screen.png').convert('RGB'))
    assert screen.shape == (600, 1600, 3) and ordinary.shape == (600, 800, 3)
    y, x = np.indices((height, width))
    raw_expected = np.stack(((x % (width // 2)) & 255, height - 1 - y,
                             ((x // (width // 2)) << 7) | (((x % (width // 2)) >> 8) << 3)), axis=2)
    if clipped:
        pixmap = native['named_pixmap']
        source = root / f'phase{index}-pixmap{pixmap["id"]}.png'
        mask = np.zeros((height, width), dtype=bool)
        for rect in native['bounding_shape']:
            mask[rect['y']:rect['y'] + rect['height'], rect['x']:rect['x'] + rect['width']] = True
        wanted = np.ones_like(mask)
        for eye in range(2):
            wanted[40:88, 40 + eye * (width // 2):72 + eye * (width // 2)] = False
        assert np.array_equal(mask, wanted), 'native clip does not match the ordinary panel'
    else:
        source = root / f'phase{index}-window{child}.png'
    raw = np.asarray(Image.open(source).convert('RGB'))
    assert np.array_equal(raw, raw_expected), 'packed source pixels changed'
    eyes = []
    for eye in range(2):
        expected = np.stack(((x // 2) & 255, height - 1 - y,
                             np.full_like(x, eye << 7) | (((x // 2) >> 8) << 3)), axis=2).astype(np.uint8)
        if clipped:
            ox, oy = old_owner['x'], old_owner['y']
            expected[40:88, 80:144] = ordinary[oy + 40:oy + 88, ox + 80:ox + 144]
        ox, oy = owner['x'] + eye * 800, owner['y']
        actual = screen[oy:oy + height, ox:ox + width]
        assert actual.shape == expected.shape
        wrong = np.any(actual != expected, axis=2)
        eyes.append({'eye': eye, 'pixels': width * height, 'wrong_pixels': int(wrong.sum()),
                     'panel_wrong_pixels': int(wrong[40:88, 80:144].sum())})
    rows.append({'phase': index, 'raw_wrong_pixels': 0, 'eyes': eyes})
wrong = sum(eye['wrong_pixels'] for row in rows for eye in row['eyes'])
print(json.dumps({'status': 'FAIL' if wrong else 'PASS', 'clipped': clipped,
                  'wrong_captured_pixels': wrong, 'phases': rows}, indent=2))
raise SystemExit(1 if wrong else 0)
