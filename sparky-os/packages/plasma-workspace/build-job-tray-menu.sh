#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# plasma-workspace 4:6.7.4-2+stereo3d10+lc1 (ORDER 108 milestone 12 round 3): the staged +stereo3d9 source plus patches/s10-0001 (the system tray's menu opens on every right click).
# Same shape as build-job-defaults.sh, one step on: the predecessor is the accepted +stereo3d9 stage (ORDER 684) mounted at /predecessor, its .dsc pinned by hash.
# Copyright 2026 under the GNU GPL3 License
# Inside an isolated build container; /work is owned scratch, /repo the published tree, /predecessor the staged +stereo3d9 files, /toolkit sparky-os.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
: "${SOURCE_DATE_EPOCH:?}" "${SOURCE_DATE_RFC2822:?}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
SRC=/predecessor
DSC=plasma-workspace_6.7.4-2+stereo3d9+lc1.dsc
cd /work
printf '%s  %s\n' 9d76d1559e44aa09e09cec1a9cca7b1434e6171ccdd47932a71e5778ef6c2028 "$SRC/$DSC" | sha256sum -c
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
cp /toolkit/packages/plasma-workspace/patches/s10-0001-systemtray-release-the-mouse-areas-around-the-applet.patch source/debian/patches/
printf '%s\n' s10-0001-systemtray-release-the-mouse-areas-around-the-applet.patch >> source/debian/patches/series
(cd source && dpkg-source --before-build .)
python3 - <<'PY'
from pathlib import Path
import os
p=Path('source/debian/changelog')
s='plasma-workspace (4:6.7.4-2+stereo3d10) unstable; urgency=medium\n\n  * The system tray releases the mouse areas around an applet when its context menu opens, so the menu opens on every right click (ORDER 108 milestone 12, ORDER 696).\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+os.environ['SOURCE_DATE_RFC2822']+'\n\n'
p.write_text(s+p.read_text())
PY
(cd source && python3 - <<'PYCODE'
from pathlib import Path
import subprocess
p=Path('debian/sparky-provenance-files')
old=p.read_text() if p.exists() else ''
subprocess.run(['python3','/toolkit/repo/provenance-files.py','.','s10-*'],check=True)
new=p.read_text()
for line in old.splitlines():
    if line and not line.startswith('#') and line not in new.splitlines():
        new+=line+'\n'
p.write_text(new)
PYCODE
)
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" source
dpkg-source -b source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/source 4:6.7.4-2+stereo3d10+lc1 --toolkit /toolkit --preserve-plan /work/published-preserve.json
printf 'deb [signed-by=/archive/sparky-stereo-repo.gpg] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/archive/deb-multimedia-keyring.gpg] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep /work/source > /work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p /work/link-scratch
chown -R builder:builder /work
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/source
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR="$SRC" SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/link-scratch dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
