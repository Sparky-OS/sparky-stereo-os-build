#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Turn `reuse lint --json` of one tree into machine-readable debian/copyright Files paragraphs.

Usage: reuse2dep5.py LINT_JSON PREFIX DEFAULT_LICENSE DEFAULT_COPYRIGHT_FILE > paragraphs
  PREFIX            '' for the main tree, 'displayxr-mcp/' for a component unpacked in that folder
  DEFAULT_LICENSE   the licence of a file that names none (the project's LICENSE covers it)
  DEFAULT_COPYRIGHT a file whose lines are the holders of a file that names none
Each file's own SPDX expressions decide its paragraph; a folder is written as FOLDER/* when every file
under it has the same licence, so the paragraphs stay file by file in meaning but short to read.
Prints the licence names it used on stderr, one per line, after 'LICENSES:'."""
import json
import re
import sys
from collections import defaultdict

lint, prefix, default_license, default_holders_file = sys.argv[1:5]
default_holders = [l.strip() for l in open(default_holders_file) if l.strip()]
files = json.load(open(lint))['files']

SPDX_EXPR = re.compile(r'^\(?[A-Za-z0-9.+-]+(?:\s+(?:AND|OR|WITH)\s+\(?[A-Za-z0-9.+-]+\)?)*\)?')


def expression(entry):
    exprs = []
    for e in entry['spdx_expressions']:
        m = SPDX_EXPR.match(e['value'].strip())
        v = m.group(0) if m else ''
        if v and v not in exprs:
            exprs.append(v)
    if not exprs:
        return default_license
    text = ' AND '.join(f'({e})' if (' OR ' in e and len(exprs) > 1) else e for e in exprs)
    return text.replace(' AND ', ' and ').replace(' OR ', ' or ')


HOLDER_PREFIX = re.compile(r'^(SPDX-FileCopyrightText:\s*)?(Copyright\s*)?(\(c\)|©)?\s*', re.I)


def holders(entry):
    out = []
    for c in entry['copyrights']:
        for line in c['value'].splitlines():
            line = HOLDER_PREFIX.sub('', line.strip()).strip().rstrip('.').rstrip('"\',;)').strip()
            line = re.sub(r'\s+', ' ', line)
            if line and line not in out:
                out.append(line)
    return out or default_holders


group_of = {}
holders_of = defaultdict(list)
for entry in files:
    path = entry['path']
    if path.startswith('.git/'):
        continue
    g = expression(entry)
    group_of[path] = g
    for h in holders(entry):
        if h not in holders_of[g]:
            holders_of[g].append(h)

# folders whose every file shares one group
folder_groups = defaultdict(set)
for path, g in group_of.items():
    parts = path.split('/')
    for i in range(1, len(parts)):
        folder_groups['/'.join(parts[:i])].add(g)

main = default_license
patterns = defaultdict(list)
covered = set()
for path in sorted(group_of):
    g = group_of[path]
    if g == main and not prefix:
        continue  # Files: * of the main tree
    parts = path.split('/')
    pattern = path
    for i in range(1, len(parts)):
        folder = '/'.join(parts[:i])
        if folder_groups[folder] == {g}:
            pattern = folder + '/*'
            break
    if pattern in covered:
        continue
    covered.add(pattern)
    patterns[g].append(prefix + pattern)

if prefix:
    order = sorted(patterns, key=lambda g: (g != main, g))
else:
    print('Files: *')
    print('Copyright: ' + '\n           '.join(sorted(holders_of[main])))
    print(f'License: {main}')
    print()
    order = sorted(patterns)
for g in order:
    print('Files: ' + '\n       '.join(sorted(patterns[g])))
    print('Copyright: ' + '\n           '.join(sorted(holders_of[g])))
    print(f'License: {g}')
    print()
names = set()
for g in list(order) + [main]:
    names.update(re.split(r'\s+(?:and|or)\s+', g.replace('(', '').replace(')', '')))
print('LICENSES: ' + ' '.join(sorted(names)), file=sys.stderr)
