#!/usr/bin/env python3
"""Strip ANSI/VT escape sequences from a serial log and print readable lines."""
import re, sys
d = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
d = re.sub(r'\x1b\[[0-9;?=]*[A-Za-z]', '\n', d)
d = d.replace('\r', '')
out = []
for l in d.split('\n'):
    l = l.rstrip()
    if not l.strip() or set(l.strip()) <= set('─│┌┐└┘ ^v*'):
        continue
    out.append(l)
# collapse consecutive duplicates
res = []
for l in out:
    if not res or res[-1] != l:
        res.append(l)
n = int(sys.argv[2]) if len(sys.argv) > 2 else 60
start = int(sys.argv[3]) if len(sys.argv) > 3 else 0
print('\n'.join(res[start:start + n]))
