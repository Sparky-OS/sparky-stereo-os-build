#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/22
# The first edition build of a Debian source with patches of ours (queue row 77 milestone 2), shared by
# packages/plasma-integration and packages/kf6-kirigami: Debian's .dsc pinned by its SHA-256, the recipe's patches
# appended to the series, its control edits, its changelog entry, provenance, Lean Code, amd64.
# Copyright 2026 under the GNU GPL3 License
# Inside an isolated build container; /work owned scratch, /src Debian's source files, /prev Debian's binary packages
# (the Lean Code link gate's predecessor), /recipe the package's recipe folder, /toolkit sparky-os, /archive the link
# gate's archive. Environment: DSC, DSC_SHA256, VERSION (the +stereo3d1 version, without +lc1), SOURCE_DATE_*.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
: "${SOURCE_DATE_EPOCH:?}" "${SOURCE_DATE_RFC2822:?}" "${DSC:?}" "${DSC_SHA256:?}" "${VERSION:?}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck'
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
cd /work
printf '%s  %s\n' "$DSC_SHA256" "/src/$DSC" | sha256sum -c
python3 - "/src/$DSC" <<'PY'
import hashlib,shutil,sys
from pathlib import Path
p=Path(sys.argv[1]);shutil.copy2(p,p.name)
for line in p.read_text().split('Checksums-Sha256:\n',1)[1].splitlines():
    if not line.startswith(' '):break
    digest,size,name=line.split();f=p.parent/name
    assert hashlib.sha256(f.read_bytes()).hexdigest()==digest,name
    shutil.copy2(f,name)
PY
dpkg-source -x "$DSC" source
# A Debian source may have no patches yet (plasma-integration 6.7.4-1 has none)
mkdir -p source/debian/patches
for p in /recipe/patches/*.patch; do
	cp "$p" source/debian/patches/
	basename "$p" >> source/debian/patches/series
done
(cd source && dpkg-source --before-build .)
# The recipe's control edits (a build dependency or a dependency its patch needs)
python3 /recipe/control-edits.py source/debian/control
python3 - <<'PY'
from pathlib import Path
import os
p=Path('source/debian/changelog')
entry=Path('/recipe/changelog-stereo3d1.txt').read_text()
assert entry.startswith(p.read_text().split(' ',1)[0]+' ('+os.environ['VERSION']+') unstable;'),entry[:80]
p.write_text(entry.rstrip('\n')+'\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+os.environ['SOURCE_DATE_RFC2822']+'\n\n'+p.read_text())
PY
(cd source && python3 /toolkit/repo/provenance-files.py . 's1-*')
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" source
dpkg-source -b source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/source "$VERSION+lc1" --toolkit /toolkit
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep /work/source > /work/build-dep.log 2>&1
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p /work/link-scratch
chown -R builder:builder /work
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/source
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/link-scratch dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
