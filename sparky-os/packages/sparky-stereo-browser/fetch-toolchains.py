#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reconstruct the accepted browser compiler bundle from pinned public archives.

Requires python3, tar, zstd and rustup. ROOT must not exist. All downloaded
Mozilla archives are hash checked before extraction; the retained source's
toolchain-manifest.json checks the complete result before configuration.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request

HERE = Path(__file__).resolve().parent


def fetch(root, cache, manifest):
    root.mkdir(parents=True, exist_ok=False)
    cache.mkdir(parents=True, exist_ok=True)
    for row in json.loads((HERE / 'toolchain-downloads.json').read_text()):
        archive = cache / (row['sha256'] + '.tar.zst')
        if not archive.exists():
            partial = archive.with_suffix('.partial')
            urllib.request.urlretrieve(row['url'], partial)
            with partial.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != row['sha256']:
                    raise ValueError('Downloaded archive hash differs: ' + row['url'])
            partial.rename(archive)
        with archive.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != row['sha256']:
                raise ValueError('Cached archive hash differs: ' + str(archive))
        destination = root / row['root']
        destination.mkdir(parents=True)
        subprocess.run(['tar', '--zstd', '--no-same-owner', '--strip-components=1',
                        '-xf', str(archive), '-C', str(destination)], check=True)

    # These are the directory aliases made by the accepted upstream fetcher.
    # Copying preserves the exact content; no compiler binary is rewritten.
    wasi = root / '.mozbuild/sysroot-wasm32-wasi'
    for directory in ('lib', 'share', 'include'):
        for old in ('wasm32-wasi', 'wasm32-wasi-threads'):
            if directory == 'include' and old.endswith('-threads'):
                continue
            source = wasi / directory / old
            target = wasi / directory / old.replace('wasi', 'wasip1')
            if source.is_dir():
                if target.exists():
                    shutil.rmtree(target)
                shutil.copytree(source, target, symlinks=True)
    clang = root / '.mozbuild/clang-22'
    for source in clang.glob('lib/clang/*/lib/wasi/libclang_rt.builtins-wasm32.a'):
        target = source.parent.parent / 'wasm32-unknown-wasip1/libclang_rt.builtins.a'
        target.parent.mkdir(exist_ok=True)
        shutil.copy2(source, target)

    env = {**os.environ, 'RUSTUP_HOME': str(root / '.rustup'),
           'CARGO_HOME': str(root / '.cargo')}
    subprocess.run(['rustup', 'toolchain', 'install',
                    '1.98.1-x86_64-unknown-linux-gnu', '--profile', 'minimal'],
                   env=env, check=True)
    subprocess.run(['python3', str(HERE / 'verify-toolchains.py'),
                    str(root), str(manifest)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--cache', type=Path, required=True)
    args = parser.parse_args()
    fetch(args.root.resolve(), args.cache.resolve(), args.manifest.resolve(strict=True))
