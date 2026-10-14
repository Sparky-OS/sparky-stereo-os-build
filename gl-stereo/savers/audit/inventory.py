#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Inventory the installed GL payload without treating a probe as qualification."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

source = Path(sys.argv[1])
output = Path(sys.argv[2])
packages = {'xscreensaver-gl': 86, 'xscreensaver-gl-extra': 45}
entries = []

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def public_credit(value):
    value = re.sub(r'\S+@\S+', '', value)
    value = re.sub(r'https?://\S+|www\.\S+', '', value)
    return ' '.join(value.replace('<>', '').split())

for package, expected in packages.items():
    version = subprocess.check_output(['dpkg-query','-W','-f=${Version}',package],text=True)
    assert version.startswith('6.09+dfsg1-2+stereo3d'), (package, version)
    paths = subprocess.check_output(['dpkg-query','-L',package],text=True).splitlines()
    binaries = [Path(p) for p in paths if Path(p).parent == Path('/usr/libexec/xscreensaver')]
    assert len(binaries) == expected, (package,len(binaries),expected)
    for binary in sorted(binaries):
        name = binary.name
        helper = name == 'mapscroller.pl'
        owner = 'mapscroller' if helper else name
        xml = source / 'hacks/config' / (owner + '.xml')
        root = ET.parse(xml).getroot()
        description = root.findtext('_description', '')
        authors = re.findall(r'Written by\s+(.+?)(?:;\s*\d{4}|\.\s*$)', description, re.S)
        files = [source/'hacks/glx'/name] if helper else list((source/'hacks/glx').glob(name+'.[cm]'))
        if name == 'companioncube':
            files = [source/'hacks/glx'/part for part in
                     ('companion.c','companion_quad.c','companion_disc.c','companion_heart.c')]
        if not files: files = list((source/'hacks').glob(name+'.c'))
        assert files, ('missing source',name)
        records = []
        for path in files:
            for line_no, line in enumerate(path.read_text(errors='replace').splitlines()[:150],1):
                if re.search(r'copyright|written by|author:', line, re.I):
                    records.append(dict(source=str(path.relative_to(source)),line=line_no,text=public_credit(line)))
        entry = dict(id=name, kind='helper' if helper else 'hack', owner=owner,
                     title=root.attrib['_label'], package=package, version=version,
                     command=[str(binary),'-window','-geometry','640x360'],
                     executable_sha256=digest(binary), settings_xml=str(xml.relative_to(source)),
                     settings_sha256=digest(xml), authors=[public_credit(x) for x in authors],
                     project_credit='Jamie Zawinski and the XScreenSaver contributors',
                     credit_records=records,
                     source_files=[str(p.relative_to(source)) for p in files],
                     qualification={'state':'pending','group':None})
        entries.append(entry)
assert len({entry['id'] for entry in entries}) == 131
assert all(entry['authors'] or entry['credit_records'] for entry in entries)
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n')
assert sum(entry['kind'] == 'hack' for entry in entries) == 130
print('PASS: 131 payload entries, 86 + 45; 130 hacks and mapscroller.pl helper; all pending qualification')
