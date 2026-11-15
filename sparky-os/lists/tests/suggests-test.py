#!/usr/bin/env python3
"""A program a task only suggests (suggests.tsv) is installed by nothing on the image: it is in no list, no role row of
roles.tsv and no integration, so it can never reach a Depends or Recommends (ORDER 575; Daniel, 2026-11-14: "keep it off by default")."""
import glob
import os
import sys

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
rows = [l.rstrip('\n').split('\t') for l in open(os.path.join(HERE, 'suggests.tsv')) if l.strip() and not l.startswith('#')]
named = set()
for path in glob.glob(os.path.join(HERE, '*.list')):
    named |= {l.split()[0] for l in open(path) if l.strip() and not l.startswith('#')}
named |= {l.split('\t')[0] for l in open(os.path.join(HERE, 'roles.tsv')) if l.strip() and not l.startswith('#')}
named |= {l.split('\t')[0] for l in open(os.path.join(HERE, 'integrations.tsv')) if l.strip() and not l.startswith('#')}
bad = [r[1] for r in rows if r[1] in named]
roles_known = {'gamer', 'designer', 'creator', 'musician', 'scientist', 'student', 'simmer', 'maker', 'engineer'}
unknown = [r[0] for r in rows if r[0] not in roles_known]
if len(rows) < 2 or bad or unknown:
    print('FAIL: rows', len(rows), 'installed by a list or a role:', bad, 'unknown roles:', unknown)
    sys.exit(1)
print('suggests.tsv: %d rows, none installed by any list, role or integration' % len(rows))
