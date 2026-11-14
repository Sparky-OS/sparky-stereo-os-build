#!/usr/bin/python3
"""An entry's tools are the entry's: no package that an entry declares as a tool may be a Depends, Pre-Depends or Recommends of the
app center package (ORDER 565; Daniel, 2026-11-14: "only when someone install vinci - same for anything that needs this sort of
dependancy"). Usage: entry-tools.py PACKAGE.deb. Reads the declarations from the package itself. Exit 1 names each offender."""
import ast
import json
import re
import subprocess
import sys

deb = sys.argv[1]


def member(path):
    data = subprocess.run(['dpkg-deb', '--fsys-tarfile', deb], check=True, capture_output=True).stdout
    return subprocess.run(['tar', '-xO', path], input=data, check=True, capture_output=True).stdout.decode()


base = './usr/lib/sparky-aptus-stereo-appcenter/'
rows = json.loads(member(base + 'catalogue.json')) + json.loads(member(base + 'main-entries.json'))
declared = {}
for row in rows:
    # the declaration's old name is refused too, so a row cannot hide its tools from this check
    for name in row.get('tools', []) + row.get('dependencies', []):
        declared.setdefault(name, set()).add(row['id'])
try:
    source = member(base + 'tools.py')
except subprocess.CalledProcessError:
    source = ''
for node in ast.walk(ast.parse(source)):
    if isinstance(node, ast.Assign) and getattr(node.targets[0], 'id', '') == 'KIND_TOOLS':
        for kind, names in ast.literal_eval(node.value).items():
            for name in names:
                declared.setdefault(name, set()).update(row['id'] for row in rows if row['kind'] == kind)
assert declared, 'no entry declares a tool: the check would prove nothing'
bad = []
for field in ('Pre-Depends', 'Depends', 'Recommends'):
    value = subprocess.run(['dpkg-deb', '-f', deb, field], check=True, capture_output=True, text=True).stdout
    for name in re.findall(r'(?:^|[,|])\s*([a-z0-9][a-z0-9+.-]*)', value):
        if name in declared:
            bad.append('%s: %s is a tool of the entry %s' % (field, name, ', '.join(sorted(declared[name]))))
for line in bad:
    print('FAIL ' + line)
if bad:
    sys.exit(1)
print('PASS no tool of an entry (%s) is a dependency of the package' % ', '.join(sorted(declared)))
