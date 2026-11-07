#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# Writes debian/sparky-provenance-files for a rebuilt Debian source (ORDER 451): the patches of the series that are ours, so that
# provenance.sh names them in the copyright file after Debian's own debian/* paragraph. Credit goes to whoever wrote the work, so
# a patch is ours only when its header says so:
#   - it has a From: or Author: line with Daniel's address, and
#   - it has no DEP-3 Origin: of upstream, backport or vendor (a carried commit stays its author's, whoever carries it).
# A patch with no From:, Author: or Origin: line stops the run and is named; nothing is guessed.
# Usage: provenance-files.py SOURCE_ROOT PATTERN...   (patterns are globs of file names under debian/patches)
import fnmatch
import re
import sys
from pathlib import Path

MINE = {'capitain_jack@yahoo.com'}
CARRIED = ('upstream', 'backport', 'vendor')
END = re.compile(r'^(---|Index: |diff |@@ |\+\+\+ )')


def header(text):
    fields = {}
    for line in text.splitlines():
        if END.match(line):
            break
        m = re.match(r'(From|Author|Origin|Co-Authored-By): *(.*)$', line, re.I)
        if m and m.group(1).lower() not in fields:
            fields[m.group(1).lower()] = m.group(2)
    return fields


def classify(text):
    """('ours' | 'other' | 'unknown', why)"""
    f = header(text)
    who = f.get('author') or f.get('from')
    if who is None and 'origin' not in f:
        return 'unknown', 'no From:, Author: or Origin: line in its header'
    origin = f.get('origin', '').strip().lower()
    if origin.startswith(CARRIED):
        return 'other', 'Origin: ' + f['origin']
    if who is None:
        return 'unknown', 'Origin: without a From: or Author: line'
    if any(a in who.lower() for a in MINE):
        return 'ours', who
    return 'other', 'by ' + who


def main(root, patterns):
    patches = Path(root) / 'debian/patches'
    names = sorted(p.name for p in patches.iterdir() if p.is_file() and any(fnmatch.fnmatchcase(p.name, g) for g in patterns))
    if not names:
        sys.exit(f'provenance-files: no patch of {patches} matches {" ".join(patterns)}')
    ours, left, unknown = [], [], []
    for name in names:
        kind, why = classify((patches / name).read_text(encoding='utf-8', errors='replace'))
        {'ours': ours, 'other': left, 'unknown': unknown}[kind].append((name, why))
    if unknown:
        sys.exit('provenance-files: cannot tell whose these are, add a DEP-3 or git header (From:/Author:, Origin:):\n' +
                 ''.join(f'  {n}: {w}\n' for n, w in unknown))
    out = ['# The files of debian/ added by Sparky Stereo OS (written by repo/provenance-files.py from the patch headers);',
           "# provenance.sh names them in the copyright file after Debian's own debian/* paragraph."]
    out += ['debian/patches/' + n for n, _ in ours]
    (Path(root) / 'debian/sparky-provenance-files').write_text('\n'.join(out) + '\n')
    for n, w in ours:
        print(f'ours   {n}')
    for n, w in left:
        print(f'left out {n} ({w})')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
