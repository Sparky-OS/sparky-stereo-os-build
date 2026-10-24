#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later
"""Compare two A10 bench phases (a10-matrix.py output), case by case.

Drops per minute count mpv's frame-drop-count and decoder-frame-drop-count
over the recorded window on the monotonic clock; the counters restart when a
looping film starts again, and those restarts are added, not subtracted.
Each case also names the Vulkan device mpv rendered on and its decoder, read
from the mpv log, with whether the output was dimmed: KWin lowers the
reference luminance of an output without a backlight when PowerDevil dims it
(63 nits of 200 at 30%), and mpv then renders SDR film as PQ for KWin to
convert. A case dimmed in one phase and not in the other is CONFOUNDED: it
compares the screen's state, not the packages.
Exit 1 when a comparable case of AFTER drops more than BEFORE, or more than
BEFORE times (1 + --tolerance) when a run-to-run spread is allowed; else 2
when a case is confounded; else 0.
Usage: compare-a10.py BEFORE_DIR AFTER_DIR [--tolerance 0.05] [--json OUT]"""
import argparse
import glob
import json
import os
import re
import sys

FEEDBACK = re.compile(r'transfer: min_luma=([0-9.]+), max_luma=([0-9.]+), ref_luma=([0-9.]+)')


def summary(path):
    rows = [json.loads(line) for line in open(path) if line.strip()]

    def value(row, key):
        prop = row['properties'].get(key, {})
        return prop.get('data') if prop.get('error') == 'success' else None

    def total(key):
        count, previous = 0, None
        for row in rows:
            current = value(row, key)
            if current is None:
                continue
            if previous is not None:
                count += current - previous if current >= previous else current
            previous = current
        return count

    seconds = rows[-1]['monotonic'] - rows[0]['monotonic']
    drops = total('frame-drop-count') + total('decoder-frame-drop-count')
    return {'seconds': round(seconds, 1), 'drops': drops, 'per_minute': round(60 * drops / seconds, 1) if seconds > 0 else None,
            'hwdec': value(rows[-1], 'hwdec-current'),
            'stereo_out': (value(rows[-1], 'video-out-params') or {}).get('stereo-in')}


def render_device(log):
    if os.path.exists(log):
        for line in open(log, errors='replace'):
            if 'Device Name:' in line:
                return line.split('Device Name:', 1)[1].strip()
    return None


def output_state(log):
    text = open(log, errors='replace').read() if os.path.exists(log) else ''
    references = [float(ref) for _, high, ref in FEEDBACK.findall(text) if float(high) > float(ref) + 0.5]
    return {'dimmed': bool(references), 'reference': min(references) if references else None,
            'pq': 'Setting preferred transfer to PQ' in text}


def phase(root):
    cases = {}
    for path in sorted(glob.glob(os.path.join(root, '*-ipc.jsonl'))):
        name = os.path.basename(path)[:-len('-ipc.jsonl')]
        cases[name] = summary(path)
        cases[name]['render'] = render_device(path[:-len('-ipc.jsonl')] + '-mpv.log')
        cases[name]['output'] = output_state(path[:-len('-ipc.jsonl')] + '-mpv.log')
    return cases


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('before')
    p.add_argument('after')
    p.add_argument('--json')
    p.add_argument('--tolerance', type=float, default=0.0, help='allowed relative spread, 0 for strict')
    a = p.parse_args()
    before, after = phase(a.before), phase(a.after)
    worse, confounded = [], []
    print(f"{'case':54} {'before/min':>10} {'after/min':>10}  verdict     after: decoder, render device, output")
    for name in sorted(set(before) | set(after)):
        b, f = before.get(name), after.get(name)
        if not b or not f:
            print(f'{name:54} missing in {"before" if not b else "after"}')
            worse.append(name)
            continue
        state = lambda case: (f"dimmed to {case['output']['reference']:g} nits{', PQ' if case['output']['pq'] else ''}"
                              if case['output']['dimmed'] else 'undimmed')
        if b['output']['dimmed'] != f['output']['dimmed']:
            verdict = 'CONFOUNDED'
            confounded.append(name)
        elif f['per_minute'] > b['per_minute'] * (1 + a.tolerance):
            verdict = 'WORSE'
            worse.append(name)
        else:
            verdict = 'ok'
        print(f"{name:54} {b['per_minute']:>10} {f['per_minute']:>10}  {verdict:10}  "
              f"{f['hwdec']}, {f['render']}, {state(f)} (before: {state(b)})")
    if a.json:
        json.dump({'before': before, 'after': after, 'worse': worse, 'confounded': confounded}, open(a.json, 'w'), indent=1)
    print('no comparable case worse than before' if not worse else f'{len(worse)} cases worse: {", ".join(worse)}')
    if confounded:
        print(f'{len(confounded)} cases confounded by a dimmed output: {", ".join(confounded)}')
    return 1 if worse else 2 if confounded else 0


if __name__ == '__main__':
    sys.exit(main())
