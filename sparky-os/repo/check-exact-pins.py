#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Find every edition package pinned to a Debian version that Debian no longer has (row 944).

An edition binary that Depends or Pre-Depends on another package at an exact version, `NAME (= VERSION)`, is
installable only while that version is the one its suite offers. When Debian testing moves NAME, apt keeps NAME and
everything that needs its new version back on every installed edition, and a fresh install cannot have both: on
2026-11-26 Debian's testing index of 20:15 UTC moved PipeWire to 1.6.11-2 while the published
pipewire-bluez5-codec-aac 1.6.9-2+aac2+lc1 said libspa-0.2-bluetooth (= 1.6.9-2), and eight PipeWire packages were
kept back. This check reads the indexes and names such a pin the day Debian moves.

    check-exact-pins.py --edition PACKAGES [--edition PACKAGES ...] --debian testing=PACKAGES [--debian unstable=PACKAGES ...]

Edition indexes are layered in order, a later record replacing an earlier one of the same package and architecture
(the published tree first, then a candidate pool). A pin on a name the edition offers (a package or a versioned
Provides) is judged against the edition's own layered records; any other pin against each Debian suite given, a
versioned Provides counting as apt counts it. The first suite is the verdict: a pin it cannot satisfy is a FAIL and
the exit status is 1. Every later suite is a warning of the next move (unstable today is testing in a few days): WARN,
exit 0 unless --fail-on-warn. --also names the other repositories an installed edition reads (NVIDIA's CUDA repository
for the driver stack, deb-multimedia, SparkyLinux); a pin one of them satisfies passes. A pin on a package none of the
indexes has is a NOTE. Only groups whose every alternative is an exact pin are judged; anything else is apt's to
resolve. Files may be plain, .gz or .xz; an unreadable file exits 2.
"""
import argparse
import gzip
import lzma
from pathlib import Path
import re
import sys

# names as Debian Policy 5.6.1 allows, and the capitals some other repositories ship (openoffice-en-US)
RELATION = re.compile(r'^\s*([A-Za-z0-9][A-Za-z0-9+._-]*)(?::[a-z0-9-]+)?\s*(?:\(\s*(<<|<=|=|>=|>>)\s*([^)\s]+)\s*\))?\s*(?:\[[^]]*\])?\s*$')


def read(path):
    data = Path(path).read_bytes()
    if path.endswith('.xz'):
        data = lzma.decompress(data)
    elif path.endswith('.gz'):
        data = gzip.decompress(data)
    return data.decode('utf-8', 'replace')


def records(path):
    for block in re.split(r'\n\s*\n', read(path)):
        fields, key = {}, None
        for line in block.splitlines():
            if line[:1] in (' ', '\t') and key:
                fields[key] += ' ' + line.strip()
            elif ':' in line:
                key, value = line.split(':', 1)
                fields[key] = value.strip()
        if fields.get('Package') and fields.get('Version'):
            yield fields


def plain(version):
    return version[2:] if version.startswith('0:') else version


def relations(text):
    """[[(name, op, version)], ...] for a Depends-style field; op and version are None when unversioned."""
    groups = []
    for group in filter(None, (g.strip() for g in text.split(','))):
        alternatives = []
        for alternative in group.split('|'):
            m = RELATION.match(alternative)
            if not m:
                raise ValueError(f'cannot read the relation {alternative.strip()!r}')
            alternatives.append((m.group(1), m.group(2), plain(m.group(3)) if m.group(3) else None))
        groups.append(alternatives)
    return groups


def offers(fields_list):
    """{name: {version: [what offers it]}} from real packages and versioned Provides."""
    seen = {}
    for f in fields_list:
        seen.setdefault(f['Package'], {}).setdefault(plain(f['Version']), []).append(f['Package'])
        for group in relations(f.get('Provides', '')):
            for name, op, version in group:
                if op == '=':
                    seen.setdefault(name, {}).setdefault(version, []).append(f['Package'])
    return seen


def edition_set(paths):
    layered = {}
    for path in paths:
        for f in records(path):
            layered[(f['Package'], f.get('Architecture', ''))] = f
    return list(layered.values())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--edition', action='append', required=True, help="an edition Packages index (repeat, in layer order)")
    parser.add_argument('--debian', action='append', required=True, metavar='SUITE=PACKAGES',
                        help='a Debian suite\'s Packages index; the first suite named is the verdict (repeat a suite for each file)')
    parser.add_argument('--also', action='append', default=[], metavar='SOURCE=PACKAGES',
                        help='another repository an installed edition reads (NVIDIA\'s CUDA repository, deb-multimedia, '
                             'SparkyLinux): a pin it satisfies passes, in the verdict and in every warning')
    parser.add_argument('--fail-on-warn', action='store_true', help='exit 1 on a later suite\'s warning as well')
    args = parser.parse_args(argv)

    def labelled(items, option):
        found = {}
        for item in items:
            label, sep, path = item.partition('=')
            if not sep or not label or not path:
                parser.error(f'{option} takes NAME=PACKAGES, not {item!r}')
            found.setdefault(label, []).append(path)
        return found

    suites = labelled(args.debian, '--debian')
    others = labelled(args.also, '--also')
    verdict_suite = next(iter(suites))
    offered = {suite: offers(f for path in paths for f in records(path)) for suite, paths in suites.items()}
    also = offers(f for paths in others.values() for path in paths for f in records(path))
    edition = edition_set(args.edition)
    ours = offers(edition)
    counts = dict(pins=0, fail=0, warn=0, note=0)
    for f in sorted(edition, key=lambda r: (r['Package'], r.get('Architecture', ''))):
        who = f"{f['Package']} {f['Version']} ({f.get('Architecture', '?')})"
        for field in ('Pre-Depends', 'Depends'):
            for group in relations(f.get(field, '')):
                if not all(op == '=' for _, op, _ in group):
                    continue
                counts['pins'] += 1
                wanted = ' | '.join(f'{n} (= {v})' for n, _, v in group)
                if any(n in ours for n, _, _ in group):
                    if not any(v in ours.get(n, {}) for n, _, v in group):
                        have = '; '.join(f"{n} {', '.join(sorted(ours.get(n, {}))) or 'none'}" for n, _, _ in group)
                        print(f'FAIL edition {who} {field} {wanted}; the edition has {have}')
                        counts['fail'] += 1
                    continue
                if not any(n in offered[s] or n in also for s in offered for n, _, _ in group):
                    print(f'NOTE {who} {field} {wanted}: in none of the indexes given')
                    counts['note'] += 1
                    continue
                if any(v in also.get(n, {}) for n, _, v in group):
                    continue
                for suite, seen in offered.items():
                    if any(v in seen.get(n, {}) for n, _, v in group):
                        continue
                    have = '; '.join(f"{n} {', '.join(sorted(set(seen.get(n, {})) | set(also.get(n, {})))) or 'none'}"
                                     for n, _, _ in group)
                    if suite == verdict_suite:
                        print(f'FAIL {suite} {who} {field} {wanted}; {suite} has {have}: rebuild it against {suite}\'s version')
                        counts['fail'] += 1
                    else:
                        print(f'WARN {suite} {who} {field} {wanted}; {suite} has {have}: {verdict_suite} will move when it migrates')
                        counts['warn'] += 1
    print(f"exact pins: {counts['pins']} checked against the edition, {', '.join(suites)}"
          f"{(' and ' + ', '.join(others)) if others else ''}; "
          f"{counts['fail']} fail, {counts['warn']} warn, {counts['note']} outside the indexes given")
    return 1 if counts['fail'] or (args.fail_on_warn and counts['warn']) else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, lzma.LZMAError) as error:
        print(f'check-exact-pins: {error}', file=sys.stderr)
        sys.exit(2)
