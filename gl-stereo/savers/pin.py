#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Name the exact packages the receipts bind, as a substvar for gl-stereo-savers' Depends.

The receipts bind the hash of every saver executable and settings file they were proved
against. The packages that own those files, at the versions installed when the receipts were
checked (install-qualified.py just proved the hashes equal), are the only ones the receipts
describe, so gl-stereo-savers depends on exactly them: apt can never pair the receipts with
another build of XScreenSaver. Nothing here is typed by hand.
"""
import json
from pathlib import Path
import subprocess
import sys

def owner(path):
    done = subprocess.run(['dpkg-query', '-S', path], capture_output=True, text=True)
    if done.returncode != 0:
        return None
    # "pkg[:arch], pkg2: /path" (a file two packages share lists both)
    return [name.split(':')[0].strip() for name in done.stdout.rsplit(': ', 1)[0].split(',')]

def version(package):
    return subprocess.run(['dpkg-query', '-W', '-f=${Version}', package], capture_output=True, text=True, check=True).stdout

def bound_files(entries):
    for entry in entries:
        yield entry['command'][0]
        settings = Path('/usr/share/xscreensaver/config')/(entry['id']+'.xml')
        if 'settings_sha256' in entry.get('verification', {}):
            yield str(settings)

def pins(entries, own=('gl-stereo', 'gl-stereo-savers'), find_owner=owner, find_version=version):
    """{package: version} of every package, other than our own, that owns a file the receipts bind."""
    found = {}
    for path in sorted(set(bound_files(entries))):
        names = find_owner(path)
        if names is None:
            if path.startswith('/usr/lib/gl-stereo/'):
                continue
            raise SystemExit('FAIL: no installed package owns %s, which a receipt binds' % path)
        for name in names:
            if name not in own:
                found[name] = find_version(name)
    if not found:
        raise SystemExit('FAIL: the receipts bind no installed package')
    return found

def substvar(found):
    return 'receipts:Pin=' + ', '.join('%s (= %s)' % item for item in sorted(found.items()))

if __name__ == '__main__':
    catalogue, substvars = sys.argv[1:3]
    line = substvar(pins(json.loads(Path(catalogue).read_text())))
    with open(substvars, 'a') as out:
        out.write(line + '\n')
    print('PASS: gl-stereo-savers depends on the exact build its receipts name: ' + line)
