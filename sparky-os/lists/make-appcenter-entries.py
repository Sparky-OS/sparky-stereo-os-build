#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
# The APTus Stereo AppCenter's integration entries, from the same list make-meta.py reads (integrations.tsv):
# for each program, the packs its installation brings, one apt call (the fork's aptus-package-install reads the map,
# see sparky-os/sparky-aptus-stereo-appcenter and the patch that goes with it).
# Usage: make-appcenter-entries.py [--packages Packages] [OUT]
#   --packages FILE  a Packages index (the repository's): a pack not in it is left out and named on stderr
#   OUT              the map file (default: standard output), program<TAB>packs per line
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import integrations

def main():
    args = sys.argv[1:]
    known = None
    if args[:1] == ['--packages']:
        known = {l.split(': ', 1)[1].strip() for l in open(args[1], errors='replace') if l.startswith('Package: ')}
        args = args[2:]
    rows = integrations.read()
    if known is not None:
        miss = [r['pack'] for r in rows if r['pack'] not in known]
        if miss:
            print('not in the repository, left out of the AppCenter map:', ' '.join(miss), file=sys.stderr)
    text = integrations.appcenter_map(rows, (lambda p: p in known) if known is not None else (lambda p: True))
    if args:
        open(args[0], 'w').write(text)
    else:
        sys.stdout.write(text)

main()
