#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/09
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/09 (ORDER 458)
"""Finds the deb-multimedia packages that ship a FILE one of our packages ships, under another package name (apt/shadowed.py), from the
Contents files of the two repositories, and exits 1 when one is in neither list of apt/shadowed.py.

A package of the same name is already blocked by name (apt/make-only-ours.py), so only another name is a pair. A shared directory is not a
file: Contents lists files only. An Architecture: all package is in Contents-all, which counts for every architecture.

  find-shadowing.py --ours DIST/dists/mashtabba/main --theirs DMO/dists/forky [--arch amd64 i386] [--components main non-free] [--quiet]

--ours is the published tree's component folder (Contents-ARCH.gz and Contents-all.gz in it), --theirs deb-multimedia's suite folder
(COMPONENT/Contents-ARCH.gz and COMPONENT/Contents-all.gz). Exit status: 0 every pair is listed, 1 a pair is not, 2 a file cannot be read.
"""
import argparse
import collections
import gzip
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'apt'))
from shadowed import NOT_SHADOWS, SHADOWED_BY_DMO  # noqa: E402

NOT_FILES = re.compile(r'^usr/share/(doc|lintian|bug|doc-base)/')


def contents(path):
    """path -> set of package names, from a Contents file (a path, a tab or spaces, then SECTION/PACKAGE[,SECTION/PACKAGE])"""
    found = collections.defaultdict(set)
    try:
        with gzip.open(path, 'rt', errors='replace') as f:
            for line in f:
                parts = line.rstrip('\n').rsplit(None, 1)
                if len(parts) != 2 or parts[0] == 'FILE':
                    continue
                for entry in parts[1].split(','):
                    found[parts[0].strip()].add(entry.rsplit('/', 1)[-1])
    except OSError as e:
        print('find-shadowing.py: %s' % e, file=sys.stderr)
        sys.exit(2)
    return found


def merged(*paths):
    out = collections.defaultdict(set)
    for p in paths:
        for k, v in contents(p).items():
            out[k] |= v
    return out


def pairs(ours_dir, theirs_dir, arches, components):
    """(theirs, ours) -> set of shared paths"""
    result = collections.defaultdict(set)
    names = set()
    for arch in arches:
        ours = merged(os.path.join(ours_dir, 'Contents-%s.gz' % arch), os.path.join(ours_dir, 'Contents-all.gz'))
        for v in ours.values():
            names |= v
        for comp in components:
            theirs = merged(os.path.join(theirs_dir, comp, 'Contents-%s.gz' % arch), os.path.join(theirs_dir, comp, 'Contents-all.gz'))
            for path, theirs_names in theirs.items():
                if path in ours and not NOT_FILES.match(path):
                    for t in theirs_names:
                        for o in ours[path]:
                            if t != o:
                                result[(t, o)].add(path)
    # a package of theirs with the name of one of ours is blocked by name already
    return {k: v for k, v in result.items() if k[0] not in names}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours', required=True)
    ap.add_argument('--theirs', required=True)
    ap.add_argument('--arch', nargs='+', default=['amd64', 'i386'])
    ap.add_argument('--components', nargs='+', default=['main', 'non-free'])
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args()
    found = pairs(a.ours, a.theirs, a.arch, a.components)
    unlisted = 0
    for (t, o), paths in sorted(found.items()):
        listed = SHADOWED_BY_DMO.get(t, (None,))[0] == o
        excused = (t, o) in NOT_SHADOWS
        state = 'listed' if listed else 'not a shadow' if excused else 'NOT LISTED'
        unlisted += not (listed or excused)
        if not a.quiet or state == 'NOT LISTED':
            print('%-11s %s <- ours %s: %d files, e.g. %s' % (state, t, o, len(paths), sorted(paths)[0]))
    for t, (o, _) in sorted(SHADOWED_BY_DMO.items()):
        if (t, o) not in found:
            print('listed but no shared file any more: %s <- %s (check apt/shadowed.py)' % (t, o), file=sys.stderr)
    return 1 if unlisted else 0


if __name__ == '__main__':
    sys.exit(main())
