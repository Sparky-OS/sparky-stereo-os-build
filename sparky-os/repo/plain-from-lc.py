#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/10/29
# Copyright 2026 under the GNU GPL3 License
"""plain-from-lc.py LC_SOURCE_DIR: undoes, in an unpacked +lc1 source tree, exactly what
sparky-os/lean/debian_prepare.py adds to a plain source (the toolkit folder, the optional
preserve plan, the six build dependencies at the front of Build-Depends, the dch entry of the
+lc1 version and the three rules targets it appends), so the tree is the plain source again.
Every step checks that the text it removes is the text debian_prepare writes; anything else stops.
The published repository holds only +lc1 sources, and the next version of a package starts from
its plain source: unpack the published .dsc (dpkg-source -x), run this on the tree, then pack it
with dpkg-source -b next to the orig tarball and its .asc.
  plain-from-lc.py [--no-build-depends] [--edition-entry] LC_SOURCE_DIR
--no-build-depends: the +lc1 source was prepared before debian_prepare added the build dependencies
(the native batch of 20 October 2026, kscreenlocker and plasma-desktop +stereo3d1+lc1 among them); the
tool then checks that Build-Depends does not start with them and leaves it as it is.
--edition-entry: the +lc1 entry also lists the edition's own changes, with no plain entry of its own
below it (the same batch, plasma-workspace +stereo3d2+lc1); the entry becomes the plain version's,
for unstable, with its other items and its signature, and only the Lean Code item removed."""
import re
import shutil
import sys
from pathlib import Path

args = sys.argv[1:]
no_build_depends = '--no-build-depends' in args
edition_entry = '--edition-entry' in args
args = [a for a in args if a not in ('--no-build-depends', '--edition-entry')]
assert len(args) == 1 and not args[0].startswith('--'), __doc__
root = Path(args[0])
deb = root / 'debian'

toolkit = deb / 'sparky-lean-toolkit'
assert toolkit.is_dir(), 'no debian/sparky-lean-toolkit: not an lc1 source'
shutil.rmtree(toolkit)
(deb / 'sparky-lean-preserve.json').unlink(missing_ok=True)

control = (deb / 'control').read_text()
prefix = 'Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml,'
if no_build_depends:
    assert prefix not in control and re.search(r'^Build-Depends: ', control, re.M), 'Build-Depends starts with the lc1 build dependencies'
else:
    assert control.count(prefix) == 1, 'the lc1 build dependencies are not where debian_prepare puts them'
    (deb / 'control').write_text(control.replace(prefix, 'Build-Depends:'))

rules = (deb / 'rules').read_text()
tail = """

# Distribution-only processing; authored source remains in the source archive.
execute_before_dh_auto_configure:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)

execute_before_dh_auto_clean:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree restore $(CURDIR)
\trm -rf .sparky-lc

override_dh_builddeb:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance $(CURDIR)/debian/sparky-lean-toolkit/provenance.sh
"""
assert rules.endswith(tail), 'the rules file does not end with the lc1 targets'
(deb / 'rules').write_text(rules[:-len(tail)] + '\n')

changelog = (deb / 'changelog').read_text()
first, body, trailer, rest = changelog.split('\n\n', 3)
m = re.match(r'(\S+) \((\S+)\+lc1\) UNRELEASED; urgency=medium$', first)
assert m, 'the first changelog entry is not an +lc1 entry: ' + first
assert trailer.startswith(' -- ') and '\n' not in trailer, trailer
lean_item = ('  * Apply verified native Lean Code before compilation and qualified lc1\n'
             '    payload assembly; retain exact authored source and HR companions.')
if edition_entry:
    items = re.split(r'\n(?=  \* )', body)
    assert items.count(lean_item) == 1 and len(items) > 1, body
    assert not rest.startswith(m.group(1) + ' (' + m.group(2) + ') '), 'a plain entry follows: run without --edition-entry'
    items.remove(lean_item)
    rest = f'{m.group(1)} ({m.group(2)}) unstable; urgency=medium\n\n' + '\n'.join(items) + '\n\n' + trailer + '\n\n' + rest
else:
    assert body.startswith('  * Apply verified native Lean Code before compilation'), body
    assert rest.startswith(m.group(1) + ' (' + m.group(2) + ') '), rest[:80]
(deb / 'changelog').write_text(rest)
print(f'{m.group(1)} {m.group(2)}+lc1 -> {m.group(2)}')
