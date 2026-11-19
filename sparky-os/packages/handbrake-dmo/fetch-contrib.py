#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain and hash-check the exact contrib archives named by this source."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    downloads = source / 'download'
    downloads.mkdir(exist_ok=True)
    records = []
    for module in ('ffmpeg', 'x265', 'x265_8bit', 'x265_10bit', 'x265_12bit'):
        text = (source / 'contrib' / module / 'module.defs').read_text()
        url = re.search(r'^\w+\.FETCH\.url\s*=\s*(https://\S+)', text, re.M)[1]
        expected = re.search(r'^\w+\.FETCH\.sha256\s*=\s*([a-f0-9]{64})', text, re.M)[1]
        name = Path(urlsplit(url).path).name
        target = downloads / name
        if not target.exists():
            subprocess.run(['curl', '--fail', '--location', '--proto', '=https',
                            '--proto-redir', '=https', '--cacert', '/run/host-ca.crt',
                            '--output', str(target), url], check=True)
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f'{module}: SHA-256 mismatch for {name}: {actual}, expected {expected}')
        records.append((name, actual, url))
    names = sorted({name for name, _, _ in records})
    (source / 'debian/source/include-binaries').write_text(''.join(f'download/{name}\n' for name in names))
    for name, digest, url in sorted(set(records)):
        print(digest, name, url)


if __name__ == '__main__':
    main()
