#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Fetch pinned outside inputs once; the separate package builder never uses the network."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('specification', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
spec = json.loads(args.specification.read_text())
args.output.mkdir(parents=True, exist_ok=True)
for name, expected in spec['files'].items():
    target = args.output / name
    if target.exists():
        if hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            raise SystemExit(f'{name}: cached checksum mismatch; refusing input')
        print(f'Cached and verified: {name}')
        continue
    url = spec['urls'][name]
    if not url.startswith('https://'):
        raise SystemExit(f'{name}: HTTPS source required')
    with urllib.request.urlopen(url, timeout=120) as response:
        if not response.url.startswith('https://'):
            raise SystemExit(f'{name}: HTTPS redirect required')
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise SystemExit(f'{name}: downloaded checksum mismatch; refusing input')
    with tempfile.NamedTemporaryFile(dir=args.output, prefix='.fetch-', delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(data)
    temporary.chmod(0o644)
    temporary.replace(target)
    print(f'Fetched and verified: {name}')
