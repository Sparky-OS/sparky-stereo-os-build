#!/usr/bin/env python3
"""Require a nonempty native loop beside every weather still in each look."""
from pathlib import Path
import sys


def main(root):
    errors = []
    sizes = (16, 22, 24, 32, 48, 64, 128, 256)
    for look in ('vector', 'photoreal', 'real'):
        for shade in ('', '-darker'):
            theme = root / f'sparky-weather-{look}{shade}'
            if not (theme / 'index.theme').is_file():
                errors.append(f'{theme}: missing index.theme')
            still_ext = '.svg' if look == 'vector' else '.png'
            loop_ext = '.loop.svgz' if look == 'vector' else '.loop.jxl'
            names = set()
            for size in sizes:
                native = theme / 'stereo' / f'{size}x{size}' / 'status'
                names.update(path.name for path in native.glob(f'weather-*{still_ext}') if not path.stem.endswith('.loop'))
            if not names:
                errors.append(f'{theme}: no weather stills')
            for size in sizes:
                native = theme / 'stereo' / f'{size}x{size}' / 'status'
                for name in sorted(names):
                    still = native / name
                    loop = still.with_suffix(loop_ext)
                    if not still.is_file() or still.stat().st_size == 0:
                        errors.append(f'{still}: missing or empty native still')
                    if not loop.is_file() or loop.stat().st_size == 0:
                        errors.append(f'{loop}: missing or empty native loop')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('Every native weather still has a native loop.')
    return 0


if __name__ == '__main__':
    sys.exit(main(Path(sys.argv[1])))
