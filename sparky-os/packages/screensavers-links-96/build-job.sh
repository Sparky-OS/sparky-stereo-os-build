#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Queue row 96: one more patch on a predecessor's +lc1 source, the link to System Settings' Screensavers page.
# The same job for kscreen, kscreenlocker, powerdevil and plasma-workspace; jobs.tsv names, for each, the predecessor's .dsc
# and its SHA-256, the successor's version, the binary package that gains the dependency on the page, and the changelog line.
# The shape is plasma-workspace/build-job-tray-menu.sh's (skill edition-packaging, one patch on a staged predecessor).
# Inside an isolated build container: /work owned scratch, /repo the published tree, /predecessor the predecessor's files,
# /toolkit sparky-os, /archive the link gate's folder, /siblings the page's own package (the link gate resolves the new Depends there).
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
: "${SOURCE_DATE_EPOCH:?}" "${SOURCE_DATE_RFC2822:?}" "${PROJECT:?kscreen, kscreenlocker, powerdevil or plasma-workspace}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
HERE=/toolkit/packages/screensavers-links-96
IFS=$'\t' read -r _ DSC SHA VERSION BINARY LINE < <(grep -P "^$PROJECT\t" "$HERE/jobs.tsv")
SRC=/predecessor
cd /work
printf '%s  %s\n' "$SHA" "$SRC/$DSC" | sha256sum -c
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
cp "$HERE/patches/$PROJECT-screensavers-link.patch" /toolkit/translations/"$PROJECT"-screensavers-link.po.patch source/debian/patches/
printf '%s\n' "$PROJECT-screensavers-link.patch" "$PROJECT-screensavers-link.po.patch" >> source/debian/patches/series
(cd source && dpkg-source --before-build .)
VERSION="$VERSION" BINARY="$BINARY" LINE="$LINE" python3 - <<'PY'
from pathlib import Path
import os, re
p=Path('source/debian/changelog')
name=p.read_text().split(' ',1)[0]
s='%s (%s) unstable; urgency=medium\n\n  * %s\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  %s\n\n' % (name, os.environ['VERSION'], os.environ['LINE'], os.environ['SOURCE_DATE_RFC2822'])
p.write_text(s+p.read_text())
# the package that carries the button depends on the page it opens
c=Path('source/debian/control'); stanzas=c.read_text().split('\n\n'); done=0
for i,stanza in enumerate(stanzas):
    if re.search(r'^Package: %s$' % re.escape(os.environ['BINARY']), stanza, re.M):
        m=re.search(r'^Depends:', stanza, re.M)
        assert m, 'no Depends in the stanza'
        stanzas[i]=stanza[:m.end()]+' sparky-stereo-screensavers,'+stanza[m.end():]; done+=1
assert done==1, done
c.write_text('\n\n'.join(stanzas))
PY
(cd source && python3 - <<'PYCODE'
from pathlib import Path
import subprocess
p=Path('debian/sparky-provenance-files')
old=p.read_text() if p.exists() else ''
subprocess.run(['python3','/toolkit/repo/provenance-files.py','.','*-screensavers-link*'],check=True)
new=p.read_text()
for line in old.splitlines():
    if line and not line.startswith('#') and line not in new.splitlines():
        new+=line+'\n'
p.write_text(new)
PYCODE
)
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" source
dpkg-source -b source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/source "$VERSION+lc1" --toolkit /toolkit --preserve-plan /work/published-preserve.json
cp /archive/sparky-stereo-repo.asc /usr/share/keyrings/sparky-stereo-repo.asc
cp /archive/deb-multimedia-keyring.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp
printf 'Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n' > /etc/apt/sources.list.d/sparky.sources
printf 'Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /usr/share/keyrings/deb-multimedia-keyring.pgp\n' > /etc/apt/sources.list.d/multimedia.sources
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --allow-downgrades --no-install-recommends build-dep /work/source > /work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p /work/link-scratch
ls /siblings/*.deb > /work/siblings.txt
chown -R builder:builder /work
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/source
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR="$SRC" SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/link-scratch SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
