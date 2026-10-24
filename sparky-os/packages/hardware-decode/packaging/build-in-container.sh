#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# /work is owned scratch, /pub the signed predecessor repository, /new the earlier
# staged cohort, /previous the published binary controls, /kit the build tree's
# packages directory, /toolkit the existing release machinery.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/new ./\n' > /etc/apt/sources.list.d/edition-new.list
printf 'deb [signed-by=/pub/sparky-stereo-repo.asc] file:/pub mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
# The staged cohort replaces its published predecessors, which the edition pin would otherwise keep.
python3 - <<'PIN' > /etc/apt/preferences.d/edition-new
for stanza in open('/new/Packages').read().split('\n\n'):
    fields = dict(line.split(': ', 1) for line in stanza.splitlines() if ': ' in line and not line.startswith(' '))
    if 'Package' in fields:
        print(f"Package: {fields['Package']}\nPin: version {fields['Version']}\nPin-Priority: 1002\n")
PIN
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends install quilt devscripts dpkg-dev > /work/prepare-deps.log 2>&1
if [ -n "${SOURCE_DSC:-}" ]; then
 cd /work
 python3 - <<'COPY_SOURCE'
import os,shutil
from pathlib import Path
p=Path('/candidate')/os.environ['SOURCE_DSC']
shutil.copy2(p,Path('/work')/p.name)
for line in p.read_text().split('Checksums-Sha256:\n',1)[1].splitlines():
 if not line.startswith(' '):break
 name=line.split()[-1]
 shutil.copy2(p.parent/name,Path('/work')/name)
COPY_SOURCE
 dpkg-source -x "$SOURCE_DSC" source > /work/prepare.log 2>&1
else
 python3 /kit/hardware-decode/packaging/build-source.py "$PKG" /work /pub /toolkit --libplacebo-source /libplacebo-input > /work/prepare.log 2>&1
fi
apt-get -y --no-install-recommends build-dep /work/source > /work/build-dep.log 2>&1
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/previous dpkg-buildpackage -us -uc ${BINARY_ONLY:--F} -j4 > /work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*.deb > /work/check-debs.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-link --previous-dir /previous /work/*.deb > /work/check-link.log 2>&1
