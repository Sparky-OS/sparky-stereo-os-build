#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Refuse any selected replacement that does not advance its published version."""
import argparse
import csv
import json
from pathlib import Path
import subprocess

from inventory import paragraphs


def greater(new, old):
    result = subprocess.run(['dpkg', '--compare-versions', new, 'gt', old],
                            capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise ValueError(result.stderr.strip())
    return result.returncode == 0


def check(candidates, published):
    latest = {}
    for row in published:
        key = (row['Package'], row.get('Architecture-Variant', ''))
        if key not in latest or greater(row['Version'], latest[key]):
            latest[key] = row['Version']
    result = []
    for row in candidates:
        key = (row['Package'], row.get('Architecture-Variant', ''))
        old = latest.get(key)
        verdict = 'new binary name' if old is None else 'PASS' if greater(row['Version'], old) else 'FAIL'
        result.append(dict(binary=key[0], architecture=row['Architecture'], variant=key[1],
                           published=old or 'absent', candidate=row['Version'],
                           verdict=verdict, path=row.get('path', '')))
    if not result:
        raise ValueError('empty candidate set')
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--published-index', type=Path, action='append', required=True,
                    help='uncompressed published Packages index; repeat for each architecture')
    ap.add_argument('--debs-file', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    published = []
    for path in args.published_index:
        published.extend(paragraphs(path.read_text()))
    if not published or any(not {'Package', 'Version', 'Architecture'} <= row.keys() for row in published):
        raise ValueError('empty or invalid published index')
    candidates = []
    for line in args.debs_file.read_text().splitlines():
        path = Path(line)
        if not line.strip() or path.is_symlink() or not path.is_file():
            raise ValueError(f'invalid binary path: {line!r}')
        control = subprocess.check_output(['dpkg-deb', '-f', str(path)], text=True)
        row = paragraphs(control)[0]
        row['path'] = str(path)
        candidates.append(row)
    result = check(candidates, published)
    with args.output.open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(result[0]), delimiter='\t')
        writer.writeheader()
        writer.writerows(result)
    failures = [r for r in result if r['verdict'] == 'FAIL']
    for row in failures:
        print(f"FAIL {row['binary']}:{row['architecture']}: NEW {row['candidate']} is not greater than PUBLISHED {row['published']}")
    print(json.dumps(dict(binaries=len(result), replacements=sum(r['published'] != 'absent' for r in result),
                          failures=len(failures))))
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
