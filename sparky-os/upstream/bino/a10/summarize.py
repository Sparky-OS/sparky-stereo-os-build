#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Produce the published/candidate presentation table from retained case marks."""
import argparse
import csv
import json
from fractions import Fraction
from pathlib import Path
from kwinframes import measure


def summarize(root):
    manifest = json.loads((root/'run.json').read_text())
    if manifest['status'] != 'complete':
        raise ValueError('Incomplete or confounded run; no comparison table')
    rate = float(Fraction(manifest['source_rate']))
    cases = measure(root/'kwin', root/'marks.csv')
    found = {c['case']: c for c in cases}
    if len(found) != 6:
        raise ValueError('Expected six completed cases')
    rows = []
    for setup, output in [('tv-3d', 'HDMI-A-1'), ('extended-hdmi', 'HDMI-A-1'), ('extended-edp', 'eDP-1')]:
        row = dict(setup=setup, output=output)
        for variant in ('published', 'candidate'):
            case = found[f'{setup}/{output}/{variant}/3d']
            row[variant+'_fps'] = case['fps']
            row[variant+'_drops_per_minute'] = max(0, rate-case['fps'])*60
        rows.append(row)
    with (root/'comparison.csv').open('w') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    lines = ['| Setup | Output | Published fps | Published drops/min | Candidate fps | Candidate drops/min |',
             '|---|---|---:|---:|---:|---:|']
    for row in rows:
        lines.append(f'| {row["setup"]} | {row["output"]} | {row["published_fps"]:.2f} | {row["published_drops_per_minute"]:.2f} | {row["candidate_fps"]:.2f} | {row["candidate_drops_per_minute"]:.2f} |')
    lines += ['', f'Source rate: {manifest["source_rate"]} fps.',
              'Drops/min is the nonnegative presentation deficit versus the source rate, not a count of identified missing video frames.',
              'KWin counts all presentations, including any non-video repaint. Raw source timestamps and rendering events are retained beside the KWin rows.']
    text = '\n'.join(lines)+'\n'
    (root/'comparison.md').write_text(text)
    (root/'kwin-counts.json').write_text(json.dumps(cases, indent=2)+'\n')
    return text


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('root', type=Path)
    print(summarize(p.parse_args().root))
