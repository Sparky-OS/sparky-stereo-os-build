#!/usr/bin/python3
# Reads `apt-get -s install` output on stdin; prints the count and the summed Installed-Size of the Inst lines.
import sys, re, subprocess
pk = []
for l in sys.stdin:
    m = re.match(r'Inst (\S+) (?:\[\S+\] )?\((\S+) ', l)
    if m: pk.append(f'{m.group(1)}={m.group(2)}')
kb = 0; seen = set()
for i in range(0, len(pk), 400):
    out = subprocess.run(['apt-cache', 'show', '--no-all-versions'] + pk[i:i+400], capture_output=True, text=True).stdout
    for st in out.split('\n\n'):
        d = dict(l.split(': ', 1) for l in st.split('\n') if ': ' in l and not l.startswith(' '))
        if 'Package' in d and d['Package'] not in seen and 'Installed-Size' in d:
            seen.add(d['Package']); kb += int(d['Installed-Size'])
print(f'packages {len(pk)}, installed size {kb/1048576:.2f} GiB ({len(pk)-len(seen)} without size)')
