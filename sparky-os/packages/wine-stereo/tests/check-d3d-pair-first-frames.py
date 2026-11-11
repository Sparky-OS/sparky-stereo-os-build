#!/usr/bin/env python3
"""Check stamped first and second Presents before and after a D3D resize."""
import argparse
import json
from pathlib import Path
import re

import numpy as np
from PIL import Image


def compare(actual, expected):
    if actual.shape != expected.shape:
        return {'pixels': int(expected.shape[0] * expected.shape[1]),
                'wrong_pixels': int(expected.shape[0] * expected.shape[1]),
                'actual_shape': list(actual.shape), 'expected_shape': list(expected.shape)}
    return {'pixels': int(expected.shape[0] * expected.shape[1]),
            'wrong_pixels': int(np.any(actual != expected, axis=2).sum()),
            'maximum_error': int(np.abs(actual.astype(int) - expected.astype(int)).max())}


def check(root, stereo):
    result = json.loads((root / 'result.json').read_text())
    assert result['returncode'] == result['trace_returncode'] == 0
    assert [p['phase'] for p in result['phases']] == list(range(4))
    log = (root / 'client.stdout').read_text()
    counts = [tuple(map(int, m)) for m in re.findall(r'phase=(\d+) .*frame=ready presents=(\d+)', log)]
    assert counts == [(0, 1), (1, 2), (2, 3), (3, 4)]
    completed = [tuple(map(int, m)) for m in re.findall(r'capture_done phase=(\d+) presents=(\d+)', log)]
    assert completed == counts
    atoms = json.loads((root / 'atoms.json').read_text())
    wire = [json.loads(line) for line in (root / 'wire.jsonl').read_text().splitlines()]
    content = [r for r in wire if r.get('opcode') == 18 and r.get('atom') == atoms['_KDE_NET_WM_STEREO_CONTENT']]
    members = [r for r in wire if r.get('opcode') == 18 and r.get('atom') == atoms['_KDE_NET_WM_STEREO_CONTENT_CHILDREN']]
    rows = []
    for phase in result['phases']:
        index = phase['phase']
        width, height = [(320, 200), (320, 200), (256, 160), (256, 160)][index]
        assert phase['logical'] == [width, height]
        windows = [w for w in phase['windows'] if w.get('raw_image_saved')]
        declared = [w for w in windows if w.get('declaration')]
        window = declared[-1] if declared else windows[-1]
        raw_name = window['named_pixmap']['file'] if window.get('named_pixmap') else f'phase{index}-window{window["id"]}.png'
        raw = np.asarray(Image.open(root / raw_name).convert('RGB'))
        y, x = np.indices((height, width))
        local_x = x % (width // 2) if stereo else x
        eye = x // (width // 2) if stereo else np.zeros_like(x)
        target = np.stack((local_x & 255, height - 1 - y,
                           (eye << 7) | ((local_x >> 8) << 3) | index), axis=2).astype(np.uint8)
        screen = np.asarray(Image.open(root / f'phase{index}-screen.png').convert('RGB'))
        eyes = []
        for e in range(2 if stereo else 1):
            local_x = x // 2 if stereo else x
            target_eye = np.stack((local_x & 255, height - 1 - y,
                                   np.full_like(x, e << 7) | ((local_x >> 8) << 3) | index), axis=2).astype(np.uint8)
            eyes.append(compare(screen[24:24 + height, 24 + e * 800:24 + e * 800 + width], target_eye))
        previous = result['phases'][index - 1]['capture_monotonic'] if index else 0
        presents = [r for r in wire if r.get('extension') == 'Present' and r.get('minor') in (1, 5)
                    and r.get('window') == window['id'] and previous < r['monotonic'] <= phase['capture_monotonic']]
        rows.append({'phase': index, 'raw': compare(raw, target), 'delivered': eyes,
                     'declared_windows': [w['id'] for w in declared], 'present_requests': len(presents)})
    return {'pixel_pass': all(not r['raw']['wrong_pixels'] and all(not e['wrong_pixels'] for e in r['delivered']) for r in rows),
            'present_pass': all(r['present_requests'] == 1 for r in rows),
            'content_writes': len(content), 'membership_writes': len(members),
            'content_windows': [r['window'] for r in content], 'counts': counts, 'phases': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--mode', choices=('mono', 'stereo'), required=True)
    args = parser.parse_args()
    result = check(args.root, args.mode == 'stereo')
    print(json.dumps(result, indent=2))
    return int(not (result['pixel_pass'] and result['present_pass']))


if __name__ == '__main__':
    raise SystemExit(main())
