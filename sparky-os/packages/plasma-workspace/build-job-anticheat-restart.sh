#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/27
# Copyright 2026 under the GNU GPL3 License
# Builds the anti-cheat restart successor of the staged restart to UEFI setup source (row 190).
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
: "${SOURCE_DATE_EPOCH:?}" "${SOURCE_DATE_RFC2822:?}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'

version=4:6.7.4-2+stereo3d14
descriptor=plasma-workspace_6.7.4-2+stereo3d13+lc1.dsc
overlay=/toolkit/packages/plasma-workspace/overlay-stereo3d14
translations=/toolkit/translations/plasma-workspace-anticheat-restart.po.patch

cd /work
printf '%s  %s\n' 98460b518b319280b4b099becf8b7c51a5f308f691f2c9191e91375e47d4a35d "/predecessor/$descriptor" | sha256sum -c
python3 - "/predecessor/$descriptor" <<'PY'
import hashlib
from pathlib import Path
import shutil
import sys

descriptor = Path(sys.argv[1])
shutil.copy2(descriptor, descriptor.name)
for row in descriptor.read_text().split("Checksums-Sha256:\n", 1)[1].splitlines():
    if not row.startswith(" "):
        break
    digest, size, name = row.split()
    source = descriptor.parent / name
    if source.stat().st_size != int(size):
        raise SystemExit(f"Size mismatch: {source}")
    with source.open("rb") as handle:
        if hashlib.file_digest(handle, "sha256").hexdigest() != digest:
            raise SystemExit(f"SHA-256 mismatch: {source}")
    shutil.copy2(source, name)
PY
dpkg-source --no-check -x "$descriptor" source
python3 /toolkit/repo/plain-from-lc.py --save-plan /work/published-preserve.json source
cp "$overlay/anticheat-restart.patch" "$translations" source/debian/patches/
printf '%s\n' anticheat-restart.patch plasma-workspace-anticheat-restart.po.patch >>source/debian/patches/series
cat "$overlay/libkworkspace.symbols" >>source/debian/libkworkspace6-6.symbols

(
    cd source
    dpkg-source --before-build .
    dch --date "$SOURCE_DATE_RFC2822" --newversion "$version" --distribution unstable \
        'Add a one-time restart for anti-cheat games to Leave, Kickoff and KRunner (row 190).'
    cp debian/sparky-provenance-files /work/previous-provenance
    python3 /toolkit/repo/provenance-files.py . '*anticheat-restart*'
    while IFS= read -r line; do
        [[ -z $line || $line == '#'* ]] && continue
        grep -Fxq -- "$line" debian/sparky-provenance-files || printf '%s\n' "$line" >>debian/sparky-provenance-files
    done </work/previous-provenance
)
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" source
dpkg-source -b source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/source "$version+lc1" --toolkit /toolkit --preserve-plan /work/published-preserve.json

cp /archive/sparky-stereo-repo.asc /usr/share/keyrings/sparky-stereo-repo.asc
cp /archive/deb-multimedia-keyring.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp
printf 'Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n' >/etc/apt/sources.list.d/sparky.sources
printf 'Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /usr/share/keyrings/deb-multimedia-keyring.pgp\n' >/etc/apt/sources.list.d/multimedia.sources
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' >/etc/apt/preferences.d/edition
apt-get --error-on=any update >/work/apt-update.log 2>&1
apt-get -y --allow-downgrades --no-install-recommends build-dep /work/source >/work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir /work/link-scratch
printf '%s\n' /siblings/*.deb >/work/siblings.txt
chown -R builder:builder /work
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/source
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/previous SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json \
    SPARKY_LC_SCRATCH=/work/link-scratch SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt dpkg-buildpackage -us -uc -j4 >/work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
