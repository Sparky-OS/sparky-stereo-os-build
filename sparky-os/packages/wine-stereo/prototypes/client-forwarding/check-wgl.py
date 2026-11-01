#!/usr/bin/env python3
"""Check captured WGL child declarations, packed eyes, delivery and clean exit.

Consumes the isolated four-case WGL rig's wgl/ directory. A historical capture
without the complete X tree can demonstrate failure, but cannot pass this gate.
This fixture samples settled phases, not the first completed Present.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def check(root):
    errors, measurements, inputs = [], [], {}
    screens = {}

    def require(condition, code, case, phase=None, **detail):
        if not condition:
            errors.append(dict(code=code, case=case, phase=phase, **detail))

    def read(path, image=False):
        data = path.read_bytes()
        inputs[str(path.relative_to(root))] = hashlib.sha256(data).hexdigest()
        if image:
            with Image.open(path) as im:
                if im.mode != 'RGB':
                    raise ValueError(f'expected RGB, got {im.mode}: {path}')
                return np.array(im)
        return json.loads(data)

    def pixels(actual, expected, code, case, phase):
        if actual.shape != expected.shape:
            require(False, code, case, phase, shape=list(actual.shape), expected=list(expected.shape))
            return
        wrong = int(np.any(actual != expected, axis=2).sum())
        measurements.append(dict(case=case, phase=phase, check=code, wrong_pixels=wrong))
        require(wrong == 0, code, case, phase, wrong_pixels=wrong)

    for bits in (32, 64):
        for mode in ('mono', 'stereo'):
            case = f'nvidia-zink-{bits}-{mode}'
            directory = root / case
            try:
                result = read(directory / 'result.json')
                exit_state = read(directory / 'exit-observation.json')
                session = read(directory / 'session.json')
                require(result['returncode'] == 0, 'client-exit', case, returncode=result['returncode'])
                require(session['returncode'] == 0, 'session-exit', case, returncode=session['returncode'])
                require(exit_state['fixture_kill'] is False, 'fixture-kill', case)
                require(exit_state['returncode'] == 0, 'observed-exit', case, returncode=exit_state['returncode'])
                require(result['support'] == [9], 'consumer-version', case, observed=result['support'])
                require(len(result['phases']) == 2, 'phase-count', case)
                for phase, (width, height) in enumerate(((320, 200), (256, 160))):
                    row = result['phases'][phase]
                    require(row['phase'] == phase and row['logical'] == [width, height], 'phase-geometry', case, phase)
                    require(row['capture'].get('returncode') == 0, 'capture', case, phase)
                    windows = row.get('all_windows', row['windows'])
                    require('all_windows' in row and 'managed_windows' in row, 'complete-topology', case, phase)
                    require(not any('error' in w for w in windows), 'window-query-error', case, phase)
                    declared = [w for w in windows if w.get('declaration') is not None]
                    require(len(declared) == (1 if mode == 'stereo' else 0), 'declaration-count', case, phase,
                            observed=[w['id'] for w in declared])
                    by_id = {w['id']: w for w in windows}
                    owners = row.get('managed_windows', [])
                    require(len(owners) == 1 and owners[0] in by_id, 'whole-window-identity', case, phase)
                    if len(owners) == 1 and owners[0] in by_id:
                        whole = by_id[owners[0]]
                        require(whole.get('declaration') is None and whole.get('declaration_version') is None,
                                'whole-window-undeclared', case, phase)
                        require(whole['width'] == width and whole['height'] == height, 'whole-window-geometry', case, phase)
                    yy, xx = np.indices((height, width))
                    left = np.stack((xx & 255, (height - 1 - yy) & 255, (xx >> 8) << 3), axis=2).astype(np.uint8)
                    right = left.copy()
                    right[:, :, 2] |= 128
                    packed = np.concatenate((left, right), axis=1)
                    # These controls act on arrays in memory; they never alter captured bytes.
                    require(not np.array_equal(np.concatenate((right, left), axis=1), packed), 'swapped-eye-control', case, phase)
                    require(not np.array_equal(np.concatenate((left, left), axis=1), packed), 'frozen-eye-control', case, phase)
                    if mode == 'stereo':
                        children = [w for w in declared if w.get('declaration_version') == [4]]
                        require(len(children) == 1, 'version4-child-count', case, phase)
                        for child in children:
                            require(child['declaration'] == [3] and child['mapped'] and
                                    child['width'] == width and child['height'] == height, 'child-contract', case, phase)
                            ancestors, current = [], child
                            while current.get('parent') in by_id and current['parent'] not in ancestors:
                                ancestors.append(current['parent'])
                                current = by_id[current['parent']]
                            require(len(owners) == 1 and owners[0] in ancestors, 'child-owner-chain', case, phase)
                            pixmap = child.get('named_pixmap', {})
                            require(pixmap.get('width') == 2 * width and pixmap.get('height') == height,
                                    'packed-geometry', case, phase)
                            if 'file' in pixmap:
                                pixels(read(directory / pixmap['file'], image=True), packed, 'packed-eyes', case, phase)
                            else:
                                require(False, 'packed-image-missing', case, phase)
                    screen = read(directory / f'phase{phase}-screen.png', image=True)
                    screens[bits, mode, phase] = screen
                    require(screen.shape == (600, 1600 if mode == 'stereo' else 800, 3), 'screen-geometry', case, phase)
                    pixels(screen[24:24+height, 24:24+width], left, 'delivered-left', case, phase)
                    if mode == 'stereo':
                        pixels(screen[24:24+height, 824:824+width], right, 'delivered-right', case, phase)
            except (OSError, ValueError, KeyError, IndexError, TypeError) as exc:
                require(False, 'incomplete-evidence', case, detail=str(exc))
    for phase, (width, height) in enumerate(((320, 200), (256, 160))):
        for bits in (32, 64):
            mono, stereo = screens.get((bits, 'mono', phase)), screens.get((bits, 'stereo', phase))
            if mono is not None and stereo is not None:
                pixels(stereo[24:24+height, 24:24+width], mono[24:24+height, 24:24+width],
                       'stereo-left-vs-mono', str(bits), phase)
        if (32, 'mono', phase) in screens and (64, 'mono', phase) in screens:
            pixels(screens[32, 'mono', phase], screens[64, 'mono', phase], 'mono-32-vs-64', 'both', phase)
    return dict(status='FAIL' if errors else 'PASS', errors=errors, measurements=measurements,
                inputs_sha256=inputs, scope='settled WGL phases; not first-Present or declaration-event counts')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path, help='Four-case wgl/ capture directory')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = check(args.root)
    with args.output.open('x') as out:
        json.dump(result, out, indent=2)
        out.write('\n')
    print(result['status'], len(result['errors']), 'errors')
    raise SystemExit(result['status'] != 'PASS')
