#!/usr/bin/env python3
"""Seed verified originals before upgrading dpkg-stereo; never edit shader files.

The bundle contains manifest.json and pristine/<sha256>.xz. Dry run is the
default. --apply only adds missing content-addressed cache entries. The updated
client owns restoration and its checks for edited or superseded files.
"""
import argparse
from contextlib import nullcontext
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import lzma
import os
from pathlib import Path
import re
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verified_bytes(path, expected):
    assert path.is_file() and not path.is_symlink(), f'Invalid cache file: {path}'
    packed = path.read_bytes()
    assert digest(lzma.decompress(packed)) == expected, f'Original hash mismatch: {path}'
    return packed


def records(state):
    rows = {}
    for path in sorted((state / 'records').glob('*.tsv')):
        for line in path.read_text().splitlines():
            if not line.strip() or line.startswith('#'):
                continue
            fields = line.split('\t')
            assert len(fields) == 11, f'Unexpected record schema: {path}'
            assert fields[0] not in rows, f'Duplicate installed record: {fields[0]}'
            rows[fields[0]] = fields
    return rows


def seed(bundle, root, apply):
    manifest = json.loads((bundle / 'manifest.json').read_text())
    state = root / 'var/lib/dpkg-stereo'
    assert (state / 'records').is_dir(), 'Expected installed per-package record index'
    if apply and root == Path('/'):
        assert os.geteuid() == 0, 'Applying to the machine needs root'
    # Use the client's own lock only when writing. Dry runs leave no state files.
    lock = (state / 'lock').open('a') if apply else nullcontext()
    with lock as held:
        if apply:
            fcntl.flock(held, fcntl.LOCK_EX)
        installed = records(state)
        cache = state / 'pristine'
        actions, inputs = [], {}
        for row in manifest['files']:
            name, expected = row['path'], row['sha256']
            assert name.startswith(('/usr/share/', '/usr/lib/')) and '..' not in Path(name).parts
            assert re.fullmatch(r'[0-9a-f]{64}', expected)
            packed = verified_bytes(bundle / 'pristine' / (expected + '.xz'), expected)
            record = installed.get(name)
            if record is None:
                actions.append(dict(path=name, state='record-already-retired'))
                continue
            assert record[4] == expected, f'Installed original changed; recapture {name}'
            assert record[7] == 'c', f'Unexpected consumer record: {name}'
            target = cache / (expected + '.xz')
            exists = target.exists() or target.is_symlink()
            if exists:
                verified_bytes(target, expected)
            else:
                inputs[expected] = packed
            current = root / name[1:]
            actions.append(dict(path=name, sha256=expected,
                                state='cached' if exists else 'seed-needed',
                                current_sha256=digest(current.read_bytes()) if current.is_file() else None,
                                recorded_lean_sha256=record[6]))
        # All records, bundle files and pre-existing cache entries are checked
        # before the first addition. Never overwrite even a damaged cache entry.
        if apply:
            cache.mkdir(exist_ok=True)
            for expected, packed in inputs.items():
                target = cache / (expected + '.xz')
                with tempfile.NamedTemporaryFile(dir=cache, prefix='.seed-', delete=False) as stream:
                    temporary = Path(stream.name)
                    stream.write(packed)
                    stream.flush()
                    os.fsync(stream.fileno())
                try:
                    os.chmod(temporary, 0o644)
                    try:
                        os.link(temporary, target)
                    except FileExistsError:
                        verified_bytes(target, expected)
                finally:
                    temporary.unlink()
            for expected in inputs:
                verified_bytes(cache / (expected + '.xz'), expected)
        return dict(state='seeded' if apply else 'dry-run', machine=manifest['machine'],
                    timestamp_utc=datetime.now(timezone.utc).isoformat(),
                    added_cache_entries=len(inputs) if apply else 0,
                    missing_cache_entries=len(inputs), files=actions,
                    scope='Only pristine cache additions; no shader, record or package changes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--root', type=Path, default=Path('/'))
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    assert not args.report.exists(), 'Preserve the earlier report; choose a new output path'
    result = seed(args.bundle.resolve(), args.root.resolve(), args.apply)
    with args.report.open('x') as stream:
        stream.write(json.dumps(result, indent=2) + '\n')
    print(result['state'], len(result['files']), 'files;', result['missing_cache_entries'],
          'missing cache entries before run;', result['added_cache_entries'], 'added')
