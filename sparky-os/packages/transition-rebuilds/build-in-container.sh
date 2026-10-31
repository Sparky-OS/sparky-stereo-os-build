#!/bin/bash
# Sparky Stereo OS: rebuilds one published +lc1 source package, unchanged, for a library transition in Debian testing.
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Runs inside a freshly updated debian:testing build container; build.sh starts it. /work is the job folder, /src the
# published +lc1 source package (its .dsc and every file it names), /prev the earlier +lc1 builds and the library the
# transition took out of the archive (the link gate's predecessor universe), /entry the changelog entry, /toolkit the build
# tree's sparky-os folder, /repo the edition's published tree (read only) and /archive the link gate's sources.json with
# the public keyrings it names. DSC names the published .dsc, DSC_SHA256 its checksum, PLAIN_OPTIONS the
# plain-from-lc.py option the source's shape needs (empty, --edition-entry, --lc-successor or --no-build-depends).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
: "${DSC:?}" "${DSC_SHA256:?}" "${PLAIN_OPTIONS?}"
printf 'deb [signed-by=/archive/sparky-stereo-repo.gpg] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/archive/deb-multimedia-keyring.gpg] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir plain && cd plain
echo "$DSC_SHA256  /src/$DSC" | sha256sum -c
python3 - <<'COPY'
import hashlib, os, shutil
from pathlib import Path
dsc = Path('/src') / os.environ['DSC']
shutil.copy2(dsc, dsc.name)
for line in dsc.read_text().split('Checksums-Sha256:\n', 1)[1].splitlines():
    if not line.startswith(' '):
        break
    digest, size, name = line.split()
    assert hashlib.sha256((dsc.parent / name).read_bytes()).hexdigest() == digest, name
    shutil.copy2(dsc.parent / name, name)
COPY
dpkg-source -x "$DSC" t >/dev/null
# shellcheck disable=SC2086
python3 /toolkit/repo/plain-from-lc.py $PLAIN_OPTIONS t
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils, re, subprocess
entry = Path('/entry').read_text()
m = re.match(r'(\S+) \((\S+)\) unstable; urgency=medium\n\n', entry)
assert m and '+lc' not in m.group(2), entry[:80]
p = Path('t/debian/changelog')
old = p.read_text()
assert old.startswith(m.group(1) + ' ('), old[:60]
current = old.split('(', 1)[1].split(')', 1)[0]
subprocess.run(['dpkg', '--compare-versions', m.group(2), 'gt', current], check=True)
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
             + email.utils.formatdate(localtime=True) + '\n\n' + old)
Path('/work/version').write_text(m.group(2) + '\n')
CHANGELOG
VERSION=$(cat /work/version)
head -12 t/debian/changelog
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
NAME=${DSC%%_*}
PLAIN_DSC=${NAME}_${VERSION#*:}.dsc
python3 - "$PLAIN_DSC" <<'COPY'
import shutil, sys
from pathlib import Path
dsc = Path('/work/plain') / sys.argv[1]
shutil.copy2(dsc, dsc.name)
for line in dsc.read_text().split('Checksums-Sha256:\n', 1)[1].splitlines():
    if not line.startswith(' '):
        break
    shutil.copy2(dsc.parent / line.split()[2], line.split()[2])
COPY
dpkg-source -x "$PLAIN_DSC" /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$VERSION+lc1" --toolkit /toolkit
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source > /work/build-dep.log 2>&1 || { tail -40 /work/build-dep.log; exit 1; }
dpkg-query -W -f='${Package}\t${Version}\n' > /work/build-environment.tsv
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" \
	SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1 || { tail -60 /work/build.log; exit 1; }
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
for deb in /work/lc/*+lc1_*.deb; do
	printf '%s\t%s\n' "$(basename "$deb")" "$(dpkg-deb -f "$deb" Depends)"
done > /work/depends.tsv
