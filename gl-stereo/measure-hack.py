#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check packed frames against depth-derived analytic correspondence.

A passing image has two nonuniform eyes, depth-bearing foreground and
horizontal texture/edges whose best correspondence agrees with the projection.
This is diagnostic capture code; it is not used by the production draw path.
"""
import sys
import json
from pathlib import Path
import numpy as np
from PIL import Image


def check(path):
    im = np.array(Image.open(path).convert('RGB'), dtype=float)
    h, width, _ = im.shape
    assert width % 2 == 0
    w = width // 2
    left, right = im[:, :w], im[:, w:]
    for eye in (left, right):
        # Spatial variation, not variation between R/G/B channels: a uniform
        # coloured eye must fail, while dim wireframes are still real scenes.
        assert eye.std(axis=(0, 1)).max() > 1, 'uniform eye'
        assert (eye.max(axis=2) > 8).mean() > .001, 'empty eye'
    all_depth = np.fromfile(path.with_suffix('.depth'), dtype=np.float32).reshape(h, width)
    depth = all_depth[:, :w]
    a, b, conv, sep = np.loadtxt(path.with_suffix('.txt'))
    if '--native-gears' in sys.argv:
        # Mesa glxgears: near=5, far=60, P00=5, eye separation=5, fixation=40.
        a, b, conv, sep = -65/55, -600/55, 40, 31.25
    assert conv > 0 and b != 0, 'no perspective metadata'
    distance = b / (2 * depth - 1 + a)
    predicted = w * sep / 100 * (1 - conv / distance)
    gradient = np.abs(left[:, 2:] - left[:, :-2]).max(axis=2)
    mask = np.zeros((h, w), dtype=bool)
    mask[:, 1:-1] = gradient > 24
    mask &= (depth > 0) & (depth < .9999) & (left.max(axis=2) > 32)
    yy, xx = np.where(mask)
    assert len(xx) >= 50, 'too few depth-bearing edges'
    dx = predicted[yy, xx]
    keep = (xx+dx > 15) & (xx+dx < w-16) & np.isfinite(dx)
    yy, xx, dx = yy[keep], xx[keep], dx[keep]
    assert len(xx) >= 50
    right_distance = b / (2 * all_depth[:, w:] - 1 + a)
    rx = np.rint(xx+dx).astype(int)
    visible = np.abs(right_distance[yy,rx] - distance[yy,xx]) < .01 * distance[yy,xx]
    assert visible.mean() > .25, 'analytic reprojection has too little depth-consistent coverage'
    yy, xx, dx = yy[visible], xx[visible], dx[visible]
    biases = np.arange(-8, 8.01, .5)
    scores = []
    for bias in biases:
        rx = np.rint(xx+dx+bias).astype(int).clip(0, w-1)
        error = np.abs(left[yy, xx] - right[yy, rx]).mean(axis=1)
        # Capped error limits disocclusion's effect while retaining mismatches.
        scores.append(np.minimum(error, 64).mean())
    best = float(biases[np.argmin(scores)])
    zero = scores[list(biases).index(0)]
    assert abs(best) <= 1, f'analytic correspondence bias {best:.1f}px (scores={scores})'
    assert min(scores) < 24, f'best correspondence colour error {min(scores):.2f}/255'
    assert min(scores) < .85 * max(scores[0], scores[-1]), 'correspondence is ambiguous'
    print(f'{path.parent.name}: edges={len(xx)} predicted disparity '
          f'10/50/90%={np.percentile(dx,[10,50,90]).round(2).tolist()} px; '
          f'measured residual={best:+.1f}px; colour error={zero:.2f}/255')
    Image.fromarray(im.astype(np.uint8)).save(path.parent/'verified.png')
    foreground = (depth > 0) & (depth < .9999) & (left.max(axis=2) > 32)
    bounds = [float(predicted[foreground].min()), float(predicted[foreground].max())]
    if '--comfort' in sys.argv:
        assert bounds[0] >= 0 and bounds[1] <= .02*w, f'outside behind-screen comfort bounds: {bounds}'
    result = dict(passed=True, oracle='depth-v1', residual_px=best,
                  disparity_bounds_px=bounds, eye_width=w, convergence=float(conv), separation=float(sep))
    (path.parent/'result.json').write_text(json.dumps(result, indent=2))
    return result


def main():
    directory = Path(sys.argv[1])
    files = sorted(directory.glob('frame-*.ppm'))
    assert files, 'no captured frames'
    complete = []
    for path in files:
        try:
            im = Image.open(path)
            size = im.width*im.height*4
            if path.with_suffix('.depth').stat().st_size == size and path.with_suffix('.txt').exists():
                complete.append(path)
        except (OSError, ValueError):
            continue
    assert complete, 'no complete captures'
    check(complete[-1])


if __name__ == '__main__':
    main()
