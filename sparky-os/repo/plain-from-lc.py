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
with dpkg-source -b next to the orig tarball and its .asc."""
import re
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
deb = root / 'debian'

toolkit = deb / 'sparky-lean-toolkit'
assert toolkit.is_dir(), 'no debian/sparky-lean-toolkit: not an lc1 source'
shutil.rmtree(toolkit)
(deb / 'sparky-lean-preserve.json').unlink(missing_ok=True)

control = (deb / 'control').read_text()
prefix = 'Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml,'
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
assert body.startswith('  * Apply verified native Lean Code before compilation'), body
assert trailer.startswith(' -- ') and '\n' not in trailer, trailer
assert rest.startswith(m.group(1) + ' (' + m.group(2) + ') '), rest[:80]
(deb / 'changelog').write_text(rest)
print(f'{m.group(1)} {m.group(2)}+lc1 -> {m.group(2)}')
