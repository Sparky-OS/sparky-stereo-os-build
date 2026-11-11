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
  plain-from-lc.py [--no-build-depends | --build-depends-at-end] [--edition-entry | --lc-successor] [--save-plan FILE | --drop-plan] LC_SOURCE_DIR
The preserve plan (ORDER 435): a source that holds debian/sparky-lean-preserve.json (the Lean Code source-consumer plan) needs
--save-plan FILE, which copies the plan to FILE (a path outside the tree, which must not exist) before the tree loses it, so
the caller hands it back to the next source with lean.debian_prepare --preserve-plan FILE, which checks it byte for byte; or
--drop-plan, for a caller that carries the plan itself (repo/lc-successor.py reads it through --save-plan too). With neither,
the tool stops before it changes anything, so no route drops a plan without saying so. A source without a plan needs neither
(--save-plan then writes no file, and FILE must not exist).
Atomic (ORDER 435): every check and every new text comes first; the tree is written only when all of them passed, so a stop
leaves it as it was.
--no-build-depends: the +lc1 source was prepared before debian_prepare added the build dependencies
(the native batch of 20 October 2026, kscreenlocker and plasma-desktop +stereo3d1+lc1 among them); the
tool then checks that Build-Depends does not start with them and leaves it as it is.
--build-depends-at-end: the +lc1 source was prepared when debian_prepare appended the six build dependencies at the
end of Build-Depends (the wheel DKMS sources of 20 October 2026, hid-tmff2-dkms 0.83+git20261010.d890a93-1+stereo3d2+lc1
among them); the tool removes them from there.
--edition-entry: the +lc1 entry also lists the edition's own changes, with no plain entry of its own
below it (the same batch, plasma-workspace +stereo3d2+lc1); the entry becomes the plain version's,
for unstable, with its other items and its signature, and only the Lean Code item removed.
--lc-successor: the +lc1 source was made straight from an earlier +lc1 source, keeping its toolkit
(sparky-os/packages/hardware-decode/prepare.py --published-lc, the ORDER 223 cohort: kdenlive
26.08.1-1+stereo3d5+lc1 among them); its first entry is the edition's own entry for unstable, the
Lean Code entry of the earlier +lc1 version lies beneath it, and that version's plain entry beneath
that. The first entry becomes the plain version's, with its items and its signature, and the earlier
Lean Code entry goes, as every plain source leaves its +lc1 entries out (ORDER 317)."""
import re
import shutil
import subprocess
import sys
from pathlib import Path

args = sys.argv[1:]
no_build_depends = '--no-build-depends' in args
at_end = '--build-depends-at-end' in args
edition_entry = '--edition-entry' in args
lc_successor = '--lc-successor' in args
drop_plan = '--drop-plan' in args
save_plan = None
if '--save-plan' in args:
    i = args.index('--save-plan')
    assert i + 1 < len(args), __doc__
    save_plan = Path(args[i + 1])
    del args[i:i + 2]
assert not (edition_entry and lc_successor) and not (no_build_depends and at_end) and not (drop_plan and save_plan), __doc__
args = [a for a in args if a not in ('--no-build-depends', '--build-depends-at-end', '--edition-entry', '--lc-successor', '--drop-plan')]
assert len(args) == 1 and not args[0].startswith('--'), __doc__
root = Path(args[0])
deb = root / 'debian'

toolkit = deb / 'sparky-lean-toolkit'
plan = deb / 'sparky-lean-preserve.json'
assert toolkit.is_dir(), 'no debian/sparky-lean-toolkit: not an lc1 source'
if plan.exists():
    assert drop_plan or save_plan, (f'{root} holds a Lean Code preserve plan (debian/sparky-lean-preserve.json): pass --save-plan FILE and hand FILE to '
                                    'lean.debian_prepare --preserve-plan, or --drop-plan if the caller carries the plan itself; nothing was changed')
if save_plan:
    assert not save_plan.exists(), f'{save_plan} exists: a plan saved by an earlier run would be taken for this source\'s'
    assert not root.resolve() in save_plan.resolve().parents, f'{save_plan} is inside the tree'

# every check and every new text first; the tree is written only after all of them passed (ORDER 435)
writes = []
control = (deb / 'control').read_text()
prefix = 'Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml,'
if no_build_depends:
    assert prefix not in control and re.search(r'^Build-Depends: ', control, re.M), 'Build-Depends starts with the lc1 build dependencies'
elif at_end:
    suffix = ', gcc, node-acorn, nodejs, perl, python3, python3-yaml\n'
    assert prefix not in control and len(re.findall(r'^Build-Depends: .*' + re.escape(suffix), control, re.M)) == 1, \
        'Build-Depends does not end with the lc1 build dependencies'
    writes.append((deb / 'control', re.sub(r'^(Build-Depends: .*)' + re.escape(suffix), lambda m: m.group(1) + '\n', control, flags=re.M)))
else:
    assert control.count(prefix) == 1, 'the lc1 build dependencies are not where debian_prepare puts them'
    writes.append((deb / 'control', control.replace(prefix, 'Build-Depends:')))

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
writes.append((deb / 'rules', rules[:-len(tail)] + '\n'))

changelog = (deb / 'changelog').read_text()
first, body, trailer, rest = changelog.split('\n\n', 3)
lean_item = ('  * Apply verified native Lean Code before compilation and qualified lc1\n'
             '    payload assembly; retain exact authored source and HR companions.')
if lc_successor:
    m = re.match(r'(\S+) \((\S+)\+lc1\) unstable; urgency=medium$', first)
    assert m, 'the first changelog entry is not an edition +lc1 entry for unstable: ' + first
    assert trailer.startswith(' -- ') and '\n' not in trailer, trailer
    assert lean_item not in body, 'the first entry has the Lean Code item: run without --lc-successor'
    lc_first, lc_body, lc_trailer, older = rest.split('\n\n', 3)
    m_lc = re.match(re.escape(m.group(1)) + r' \((\S+)\+lc1\) UNRELEASED; urgency=medium$', lc_first)
    assert m_lc, 'no earlier Lean Code entry beneath the first: ' + lc_first
    assert lc_body == lean_item, 'the earlier +lc1 entry has more than the Lean Code item: ' + lc_body
    assert lc_trailer.startswith(' -- ') and '\n' not in lc_trailer, lc_trailer
    assert older.startswith(m.group(1) + ' (' + m_lc.group(1) + ') '), 'the earlier plain entry does not follow: ' + older[:80]
    assert subprocess.run(['dpkg', '--compare-versions', m.group(2), 'gt', m_lc.group(1)]).returncode == 0, (m.group(2), m_lc.group(1))
    writes.append((deb / 'changelog', f'{m.group(1)} ({m.group(2)}) unstable; urgency=medium\n\n' + body + '\n\n' + trailer + '\n\n' + older))
    message = f'{m.group(1)} {m.group(2)}+lc1 -> {m.group(2)} (the {m_lc.group(1)}+lc1 Lean Code entry left out)'
else:
    m = re.match(r'(\S+) \((\S+)\+lc1\) UNRELEASED; urgency=medium$', first)
    assert m, 'the first changelog entry is not an +lc1 entry: ' + first
    assert trailer.startswith(' -- ') and '\n' not in trailer, trailer
    if edition_entry:
        items = re.split(r'\n(?=  \* )', body)
        assert items.count(lean_item) == 1 and len(items) > 1, body
        assert not rest.startswith(m.group(1) + ' (' + m.group(2) + ') '), 'a plain entry follows: run without --edition-entry'
        items.remove(lean_item)
        rest = f'{m.group(1)} ({m.group(2)}) unstable; urgency=medium\n\n' + '\n'.join(items) + '\n\n' + trailer + '\n\n' + rest
    else:
        assert body.startswith('  * Apply verified native Lean Code before compilation'), body
        assert rest.startswith(m.group(1) + ' (' + m.group(2) + ') '), rest[:80]
    writes.append((deb / 'changelog', rest))
    message = f'{m.group(1)} {m.group(2)}+lc1 -> {m.group(2)}'

if save_plan and plan.exists():
    shutil.copyfile(plan, save_plan)
for path, text in writes:
    path.write_text(text)
shutil.rmtree(toolkit)
plan.unlink(missing_ok=True)
print(message)
