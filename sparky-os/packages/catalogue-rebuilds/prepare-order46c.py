#!/usr/bin/env python3
"""Prepare an exact published program source for its edition catalogue successor."""

import argparse
import csv
from pathlib import Path
import shutil
import subprocess


HERE = Path(__file__).resolve().parent


def run(*args, directory):
    return subprocess.check_output(args, cwd=directory, text=True).strip()


def prepare(root, plan):
    source = run('dpkg-parsechangelog', '-SSource', directory=root)
    base = run('dpkg-parsechangelog', '-SVersion', directory=root)
    if (source, base) != (plan['source'], plan['base_version']):
        raise ValueError(f'Expected {plan["source"]} {plan["base_version"]}, got {source} {base}')
    patch = HERE.parent.parent / 'translations' / plan['patch']
    run('patch', '--batch', '--forward', '--fuzz=0', '--dry-run', '-p1', '-i', patch, directory=root)
    source_format = (root / 'debian/source/format').read_text().strip()
    if source_format == '3.0 (quilt)':
        patches = root / 'debian/patches'
        patches.mkdir(exist_ok=True)
        series = patches / 'series'
        preceding = series.read_bytes() if series.exists() else b''
        target = patches / patch.name
        if target.exists():
            raise ValueError(f'{target} already exists')
        shutil.copyfile(patch, target)
        with series.open('wb') as stream:
            stream.write(preceding.rstrip(b'\n') + b'\n' if preceding else b'')
            stream.write(patch.name.encode() + b'\n')
        run('dpkg-source', '--before-build', '.', directory=root)
    elif source_format == '3.0 (native)':
        run('patch', '--batch', '--forward', '--fuzz=0', '-p1', '-i', patch, directory=root)
    else:
        raise ValueError(f'{source}: unsupported source format {source_format}')
    changelog = root / 'debian/changelog'
    entry = (HERE / 'entries' / plan['entry']).read_bytes()
    changelog.write_bytes(entry + b'\n' + changelog.read_bytes())
    version = run('dpkg-parsechangelog', '-SVersion', directory=root)
    if version != plan['candidate_version']:
        raise ValueError(f'{source}: expected candidate {plan["candidate_version"]}, got {version}')
    print(source, base, version, source_format, patch.name, sep='\t')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_tree', type=Path)
    args = parser.parse_args()
    root = args.source_tree.resolve()
    source = run('dpkg-parsechangelog', '-SSource', directory=root)
    with (HERE / 'order46c-receivers.tsv').open() as stream:
        plans = {row['source']: row for row in csv.DictReader(stream, delimiter='\t')}
    if source not in plans:
        parser.error(f'{source} has no ORDER 46 program catalogue plan')
    prepare(root, plans[source])


if __name__ == '__main__':
    main()
