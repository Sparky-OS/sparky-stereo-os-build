#!/usr/bin/env python3
"""Verify the new routes against previously qualified software source samples."""
import argparse, csv
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('work', type=Path)
p.add_argument('reference', type=Path)
a = p.parse_args()
for pair in ('amd-only', 'nvidia-only', 'hybrid-amd', 'hybrid-nvidia'):
    for engine in ('mlt', 'qt', 'vlc'):
        directory = a.work/'final'/f'final-{ "vlc" if engine == "vlc" else "engine" }-clients-{pair}'
        assert (directory/'passed.txt').exists(), directory
        for name in ('h264-eyes8', 'h264-eyes10', 'hevc-eyes10', 'hevc-eyes12', 'h264-2d8', 'h264-right8', 'h264-cancel8'):
            actual = directory/f'{engine}-{name}.raw'
            refdir = 'amd-cancel-recorded' if 'cancel' in name else 'amd-engines'
            reference = a.reference/'final'/refdir/f'{"qt" if engine == "vlc" else engine}-{"software" if "cancel" in name else name+"-software"}.raw'
            expected = reference.read_bytes()
            pixels = actual.read_bytes()
            if engine == 'vlc':
                frame = 640*192*2
                sources = {expected[i:i+frame] for i in range(0,len(expected),frame)}
                assert len(pixels) >= frame and len(pixels)%frame == 0, actual
                assert all(pixels[i:i+frame] in sources for i in range(0,len(pixels),frame)), actual
            else:
                assert pixels == expected, actual
            rows = list(csv.reader(actual.with_suffix('.trace').read_text().splitlines()))
            assert rows, actual
            bits = 12 if name.endswith('12') else 10 if name.endswith('10') else 8
            for r in rows:
                assert int(r[4]) == bits, (actual,r)
                unmarked = '2d' in name or ('cancel' in name and int(r[1]) >= (2000001 if engine == 'vlc' else 2000))
                assert int(r[5]) in ((-1, 0) if unmarked else (1,)), (actual,r)
                assert int(r[6]) == int('right' in name), (actual,r)
            # Driver capabilities are checked before selecting hardware.
            expected_api = 'cuda' if 'nvidia' in pair else 'vaapi'
            if name == 'h264-eyes10' or name == 'hevc-eyes12' and (pair == 'amd-only' or engine == 'vlc'):
                assert all(r[7] == '0' for r in rows), (actual,rows[0])
            elif 'cancel' not in name:
                if name == 'hevc-eyes12': expected_api = 'cuda'
                assert all(r[2] == expected_api and r[7] == '1' for r in rows), (actual,rows[0])
        print(pair, engine, 'samples, precision, layout, cancellation and decoder PASS')
print('PASS: 84 native decoder runs')
