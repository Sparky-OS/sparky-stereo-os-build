#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""ORDER 242 adaptation of the main session's a10-inputs/kwinframes.py.

The measure is unchanged: count pageflip timestamps in [case start, case end).
A caller-supplied log directory replaces the old dated, home-relative directory.
"""
import argparse
import bisect
import csv
import json
from pathlib import Path


def measure(logdir, marks_file):
    flips = {}
    for output in ('eDP-1', 'HDMI-A-1'):
        path = logdir / f'kwin perf statistics {output}.csv'
        if not path.exists():
            continue
        with path.open() as handle:
            reader = csv.reader(handle)
            header = next(reader)
            if header[1] != 'pageflip timestamp':
                raise ValueError(f'Unexpected KWin header: {path}')
            flips[output] = sorted(int(row[1]) / 1e9 for row in reader)
    with marks_file.open() as handle:
        pairs = list(csv.reader(handle))
    marks = {name: float(value) for name, value in pairs}
    if len(marks) != len(pairs):
        raise ValueError('Duplicate case marks')
    result = []
    for name, start in marks.items():
        if name.endswith('-end') or name.endswith('/idle'):
            continue
        end = marks.get(name + '-end')
        if end is None or end <= start:
            raise ValueError(f'Missing or invalid end mark: {name}')
        output = name.split('/')[1]
        times = flips[output]
        count = bisect.bisect_left(times, end) - bisect.bisect_left(times, start)
        if not count:
            raise ValueError(f'No KWin rows for {name}')
        result.append(dict(case=name, output=output, frames=count,
                           seconds=end-start, fps=count/(end-start)))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logdir', required=True, type=Path)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    print(json.dumps(measure(args.logdir, args.root/'marks.csv'), indent=2))
