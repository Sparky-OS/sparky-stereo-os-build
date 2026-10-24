# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
# Reads integrations.tsv, the one list of the edition's stereo integration packs (make-meta.py and
# make-appcenter-entries.py both read it here, so nothing is typed twice).
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ('data', 'native')

def read(path=None):
    rows, seen = [], set()
    with open(path or os.path.join(HERE, 'integrations.tsv')) as f:
        lines = f.readlines()
    for n, l in enumerate(lines, 1):
        if not l.strip() or l.startswith('#'):
            continue
        c = l.rstrip('\n').split('\t')
        if len(c) < 3 or c[2] not in KINDS or not re.fullmatch(r'sparky-stereo-[a-z0-9][a-z0-9.+-]*', c[1]):
            sys.exit(f'integrations.tsv line {n}: want program, sparky-stereo-<name>, data|native')
        if c[1] in seen:
            sys.exit(f'integrations.tsv line {n}: {c[1]} is listed twice')
        seen.add(c[1])
        rows.append({'program': c[0], 'pack': c[1], 'kind': c[2], 'notes': c[3] if len(c) > 3 else ''})
    return rows

def appcenter_map(rows, have=lambda pack: True):
    # program <TAB> the packs the AppCenter installs with it (apt skips what is installed already)
    by = {}
    for r in rows:
        if have(r['pack']):
            by.setdefault(r['program'], []).append(r['pack'])
    return ''.join(f'{p}\t{" ".join(sorted(packs))}\n' for p, packs in sorted(by.items()))
