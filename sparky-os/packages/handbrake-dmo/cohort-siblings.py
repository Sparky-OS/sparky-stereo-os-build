#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build one authoritative sibling list, omitting the candidate's own packages."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('work', type=Path)
parser.add_argument('repository', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--candidate', required=True)
parser.add_argument('--replace', action='append', default=[])
args = parser.parse_args()
work, repository = args.work.resolve(), args.repository.resolve()

def package(path):
    return subprocess.check_output(['dpkg-deb', '-f', str(path), 'Package'], text=True).strip()

def archives(name):
    return sorted((work / name).glob('*.deb'))

excluded = {package(p) for p in archives(args.candidate)}
replacements = {}
for folder in args.replace:
    for p in archives(folder):
        name = package(p)
        excluded.add(name)
        if '-dbgsym_' not in p.name:
            replacements[name] = '/work/' + str(p.relative_to(work))
selected = {}
for line in (work / 'siblings.txt').read_text().splitlines():
    if line.startswith('/repo/'):
        path = repository / line.removeprefix('/repo/')
    elif line.startswith('/work/'):
        path = work / line.removeprefix('/work/')
    else:
        raise ValueError(line)
    name = package(path)
    if name not in excluded:
        if name in selected and line != selected[name]:
            raise ValueError('Conflicting sibling: ' + name)
        selected[name] = line
selected.update(replacements)
args.output.write_text('\n'.join(selected[name] for name in sorted(selected)) + '\n')
print(len(selected), 'authoritative sibling packages')
