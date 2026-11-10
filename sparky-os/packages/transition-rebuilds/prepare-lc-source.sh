#!/bin/bash
# Sparky Stereo OS: turns a published +lc1 source back into its plain source, adds one changelog entry and prepares the next
# +lc1 source; the first half of a transition rebuild (build-in-container.sh runs it, tests/reproducible-sources runs it on a fixture).
# Created by Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# The published source's Lean Code source-consumer plan (debian/sparky-lean-preserve.json) is saved by plain-from-lc.py
# (--save-plan) and handed back to lean.debian_prepare (--preserve-plan), the shared way of every route (ORDER 433, 435). The new
# plan must equal the published one byte for byte; otherwise debian_prepare stops and names the source, and no source is written
# that lost its plan.
# Folders (environment, the defaults are the container's): WORK, SRC (the published .dsc and every file it names), ENTRY (the
# changelog entry file), TOOLKIT (the build tree's sparky-os folder), REPRODUCIBLE (repo/reproducible.py).
# Needs: DSC, DSC_SHA256, PLAIN_OPTIONS (empty, --edition-entry, --lc-successor or --no-build-depends), SOURCE_DATE_EPOCH and
# SOURCE_DATE_RFC2822. Leaves the plain source package in WORK/plain and the +lc1 source tree in WORK/lc/source.
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
: "${DSC:?}" "${DSC_SHA256:?}" "${PLAIN_OPTIONS?}"
export WORK=${WORK:-/work} SRC=${SRC:-/src} ENTRY=${ENTRY:-/entry} TOOLKIT=${TOOLKIT:-/toolkit} REPRODUCIBLE=${REPRODUCIBLE:-/run/reproducible.py}
cd "$WORK"
mkdir plain && cd plain
echo "$DSC_SHA256  $SRC/$DSC" | sha256sum -c
python3 - <<'COPY'
import hashlib, os, shutil
from pathlib import Path
dsc = Path(os.environ['SRC']) / os.environ['DSC']
shutil.copy2(dsc, dsc.name)
for line in dsc.read_text().split('Checksums-Sha256:\n', 1)[1].splitlines():
    if not line.startswith(' '):
        break
    digest, size, name = line.split()
    assert hashlib.sha256((dsc.parent / name).read_bytes()).hexdigest() == digest, name
    shutil.copy2(dsc.parent / name, name)
COPY
dpkg-source -x "$DSC" t >/dev/null
# the published plan is saved beside the tree and handed back to lean.debian_prepare, which checks it byte for byte (ORDER 435)
python3 "$TOOLKIT/repo/plain-from-lc.py" $PLAIN_OPTIONS --save-plan "$WORK/published-preserve.json" t
python3 - <<'CHANGELOG'
from pathlib import Path
import os, re, subprocess
entry = Path(os.environ['ENTRY']).read_text()
m = re.match(r'(\S+) \((\S+)\) unstable; urgency=medium\n\n', entry)
assert m and '+lc' not in m.group(2), entry[:80]
p = Path('t/debian/changelog')
old = p.read_text()
assert old.startswith(m.group(1) + ' ('), old[:60]
current = old.split('(', 1)[1].split(')', 1)[0]
subprocess.run(['dpkg', '--compare-versions', m.group(2), 'gt', current], check=True)
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
             + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + old)
Path(os.environ['WORK'], 'version').write_text(m.group(2) + '\n')
CHANGELOG
VERSION=$(cat "$WORK/version")
head -12 t/debian/changelog
python3 "$REPRODUCIBLE" normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p "$WORK/lc" && cd "$WORK/lc"
NAME=${DSC%%_*}
PLAIN_DSC=${NAME}_${VERSION#*:}.dsc
python3 - "$PLAIN_DSC" <<'COPY'
import os, shutil, sys
from pathlib import Path
dsc = Path(os.environ['WORK'], 'plain', sys.argv[1])
shutil.copy2(dsc, dsc.name)
for line in dsc.read_text().split('Checksums-Sha256:\n', 1)[1].splitlines():
    if not line.startswith(' '):
        break
    shutil.copy2(dsc.parent / line.split()[2], line.split()[2])
COPY
dpkg-source -x "$PLAIN_DSC" "$WORK/lc/source" >/dev/null
cd "$WORK/lc/source"
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare "$WORK/lc/source" "$VERSION+lc1" --toolkit "$TOOLKIT" --preserve-plan "$WORK/published-preserve.json"
