#!/usr/bin/env python3
"""Verify the real rejected/accepted package controls, without running payloads."""
import json
import sys
from pathlib import Path
red, green = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
module = './usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/kcms/systemsettings/kcm_krdpserver.so'
r = next(p for p in red['packages'] if p['package'] == 'krdp')
r = next(e for e in r['elf'] if e['path'] == module)
assert r['neededRemoved'] == ['libsystemd.so.0']
assert len(r['old']['undefinedByLibrary']['libsystemd.so.0']) == 9
assert 'libsystemd.so.0' not in r['new']['undefinedByLibrary']
count = 0
for package in green['packages']:
    for entry in package['elf']:
        old, new = entry['old'], entry['new']
        assert old and new, entry['path']
        assert old['needed'] == new['needed'], entry['path']
        assert old['soname'] == new['soname'], entry['path']
        assert old['undefinedDynamicSymbols'] == new['undefinedDynamicSymbols'], entry['path']
        assert not old['missingClosureLibraries'] and not new['missingClosureLibraries'], entry['path']
        count += 1
print('RED: rejected KCM loses libsystemd.so.0 and all nine systemd imports: detected')
print(f'GREEN: {len(green["packages"])} packages, {count} ELFs; exact NEEDED order, SONAME and undefined imports match; complete static library closures')
