#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/22
# kf6-kiconthemes 6.32.0-1+stereo3d3+lc1 (queue row 77 milestone 2): the staged +stereo3d2 source plus
# patches/s3-0001 (each drawing of an icon the theme has in stereo is counted on the application, so that the KDE
# platform theme and Kirigami's Icon learn which windows show such icons).
# Same shape as packages/plasma-workspace/build-job-tray-menu.sh: one step on from a predecessor pinned by hash.
# Copyright 2026 under the GNU GPL3 License
# Inside an isolated build container; /work is owned scratch, /repo the published tree, /predecessor the folder of
# the +stereo3d2 files, /toolkit sparky-os, /archive the archive file of the link gate.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
: "${SOURCE_DATE_EPOCH:?}" "${SOURCE_DATE_RFC2822:?}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
SRC=/predecessor
DSC=kf6-kiconthemes_6.32.0-1+stereo3d2+lc1.dsc
cd /work
printf '%s  %s\n' a22375790591f495f537b935aee8bec4708619cf39db9075c02f95162d740a7a "$SRC/$DSC" | sha256sum -c
python3 - "$SRC/$DSC" <<'PY'
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
python3 /toolkit/repo/plain-from-lc.py --save-plan /work/published-preserve.json source
for p in s3-0001-stereo-icons-a-drawing-is-counted.patch; do
	cp "/toolkit/packages/kf6-kiconthemes/patches/$p" source/debian/patches/
	printf '%s\n' "$p" >> source/debian/patches/series
done
(cd source && dpkg-source --before-build .)
python3 - <<'PY'
from pathlib import Path
import os
p=Path('source/debian/changelog')
s=('kf6-kiconthemes (6.32.0-1+stereo3d3) unstable; urgency=medium\n\n'
   '  * Each drawing of an icon the theme has in stereo, in either eye of a window drawn once per eye or\n'
   '    as the plain icon outside an eye pass, adds one to the application\'s _q_stereo_icons_drawn, so that\n'
   '    the KDE platform theme and Kirigami\'s Icon learn which windows show such icons; a theme without\n'
   '    stereo folders is not looked up (row 77 milestone 2).\n\n'
   ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+os.environ['SOURCE_DATE_RFC2822']+'\n\n')
p.write_text(s+p.read_text())
PY
(cd source && python3 - <<'PYCODE'
from pathlib import Path
import subprocess
p=Path('debian/sparky-provenance-files')
old=p.read_text() if p.exists() else ''
subprocess.run(['python3','/toolkit/repo/provenance-files.py','.','s3-*'],check=True)
new=p.read_text()
for line in old.splitlines():
    if line and not line.startswith('#') and line not in new.splitlines():
        new+=line+'\n'
p.write_text(new)
PYCODE
)
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" source
dpkg-source -b source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/source 6.32.0-1+stereo3d3+lc1 --toolkit /toolkit --preserve-plan /work/published-preserve.json
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep /work/source > /work/build-dep.log 2>&1
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p /work/link-scratch
chown -R builder:builder /work
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/source
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR="$SRC" SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/link-scratch dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
