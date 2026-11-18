#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Retain dpkg-deb listings and compare every payload member with published bytes."""
import argparse
from collections import Counter
import concurrent.futures
import csv
import difflib
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

from reconcile import write_tsv


def member_name(name):
    """dpkg-deb prints directory slashes that tar member names may omit."""
    return name.removeprefix('./').rstrip('/') or '.'


def listing_name(line):
    fields = line.split(None, 5)
    if len(fields) != 6:
        raise ValueError('unreadable dpkg-deb listing line: ' + line)
    return member_name(fields[5].split(' -> ', 1)[0].split(' link to ', 1)[0])


def members(path):
    result = {}
    child = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with tarfile.open(fileobj=child.stdout, mode='r|') as archive:
        for entry in archive:
            name = member_name(entry.name)
            digest = ''
            if entry.isfile():
                h = hashlib.sha256()
                stream = archive.extractfile(entry)
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    h.update(block)
                digest = h.hexdigest()
            result[name] = {'type': entry.type.decode('ascii'), 'mode': oct(entry.mode),
                            'uid': entry.uid, 'gid': entry.gid, 'link': entry.linkname,
                            'size': entry.size, 'sha256': digest}
    child.stdout.close()
    error = child.stderr.read().decode(errors='replace')
    if child.wait():
        raise ValueError(str(path) + ': ' + error)
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('files', type=Path)
    ap.add_argument('inventory', type=Path)
    ap.add_argument('--published', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--explanations', type=Path, action='append', default=[],
                    help='reviewed TSV with binary, path, reason columns; retained separately from the diff')
    args = ap.parse_args()
    explanations = {}
    for path in args.explanations:
        for row in csv.DictReader(path.open(), delimiter='\t'):
            explanations[(row['binary'], member_name(row['path']))] = row['reason']
    rows = list(csv.DictReader(args.files.open(), delimiter='\t'))
    candidates = [r for r in rows if r['kind'] == 'binary' and r['decision'] == 'candidate']
    published = {(r['binary'], r['architecture'], r.get('variant', '')): r
                 for r in json.loads(args.inventory.read_text())['published'] if r['kind'] == 'binary'}
    args.output.mkdir(exist_ok=True, parents=True)
    def inspect(row):
        binary, arch, variant = row['binary'], row['architecture'], row.get('variant', '')
        key = (binary, arch, variant)
        new = Path(row['stage']) / row['filename']
        prior = published.get(key)
        out = args.output / (binary + '_' + (variant or arch))
        out.mkdir(exist_ok=True)
        listing = subprocess.check_output(['dpkg-deb', '-c', str(new)], text=True)
        (out / 'new.list').write_text(listing)
        right = members(new)
        left, previous_listing = {}, ''
        if prior:
            old = args.published / prior['filename']
            previous_listing = subprocess.check_output(['dpkg-deb', '-c', str(old)], text=True)
            (out / 'published.list').write_text(previous_listing)
            left = members(old)
        (out / 'listing.diff').write_text(''.join(difflib.unified_diff(previous_listing.splitlines(True), listing.splitlines(True), fromfile='published', tofile='candidate')))
        differences = []
        for path in sorted(set(left) | set(right)):
            before, after = left.get(path), right.get(path)
            if before == after:
                continue
            if before is None:
                action, reason = 'added', 'New payload member'
            elif after is None:
                action = 'removed'
                if before['type'] == '5':
                    reason = 'Directory removed; descendant files are compared separately'
                elif '/.build-id/' in '/' + path and binary.endswith('-dbgsym'):
                    reason = 'Version-specific debug build ID replaced by successor debug archive; executable family retained'
                else:
                    reason = 'REVIEW REQUIRED: published payload path absent from successor'
            else:
                action, reason = 'changed', 'Path remains; content/metadata differences are recorded explicitly'
            if action == 'removed' and (binary, path) in explanations:
                reason = explanations[(binary, path)]
            differences.append({'binary': binary, 'architecture': arch, 'path': path,
                                'action': action, 'reason': reason,
                                'published': json.dumps(before, sort_keys=True), 'candidate': json.dumps(after, sort_keys=True)})
        # Every removed listing line is mapped even when only its timestamp/size changed.
        removed_lines = []
        for line in difflib.unified_diff(previous_listing.splitlines(), listing.splitlines()):
            if line.startswith('-') and not line.startswith('---'):
                path = listing_name(line[1:])
                reason = ('Payload path remains; listing metadata/size/time changed' if path in right
                          else next((r['reason'] for r in differences if r['path'] == path), 'REVIEW REQUIRED: listing path unresolved'))
                removed_lines.append({'binary': binary, 'architecture': arch, 'line': line[1:], 'path': path, 'reason': reason})
        write_tsv(out / 'members.tsv', differences, ['binary', 'architecture', 'path', 'action', 'reason', 'published', 'candidate'])
        write_tsv(out / 'listing-left.tsv', removed_lines, ['binary', 'architecture', 'line', 'path', 'reason'])
        return {'binary': binary, 'architecture': arch, 'published_version': prior['version'] if prior else 'absent',
                'candidate_version': row['version'], 'published_members': len(left), 'candidate_members': len(right),
                'removed': sum(r['action'] == 'removed' for r in differences),
                'unexplained': sum(r['reason'].startswith('REVIEW REQUIRED') for r in differences),
                'listing_lines_left': len(removed_lines), 'output': str(out)}, differences, removed_lines
    results, differences, lines = [], [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for summary, changes, listing_lines in pool.map(inspect, candidates):
            results.append(summary); differences.extend(changes); lines.extend(listing_lines)
            print(summary['binary'], summary['removed'], 'removed,', summary['unexplained'], 'need explanation', flush=True)
    (args.output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
    write_tsv(args.output / 'removed-members.tsv', [r for r in differences if r['action'] == 'removed'],
              ['binary', 'architecture', 'path', 'action', 'reason', 'published', 'candidate'])
    write_tsv(args.output / 'listing-left.tsv', lines, ['binary', 'architecture', 'line', 'path', 'reason'])
    print('Compared', len(results), 'binary archives;', sum(r['unexplained'] for r in results), 'removed paths need explanation')


if __name__ == '__main__':
    main()
