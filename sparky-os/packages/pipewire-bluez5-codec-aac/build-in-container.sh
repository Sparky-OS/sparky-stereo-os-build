#!/bin/bash
# This entry point runs in the disposable container created by build.sh.
set -euo pipefail
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
export SOURCE_DATE_EPOCH
export DEBIAN_FRONTEND=noninteractive
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4

sed -i 's/^Types: deb$/Types: deb deb-src/; s/^Components: main$/Components: main contrib non-free non-free-firmware/' \
    /etc/apt/sources.list.d/debian.sources
apt-get -q update
apt-get -y --no-install-recommends install build-essential debhelper devscripts \
    debian-keyring gnupg python3
# python3 exists only from here on in a bare debian:testing image
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_RFC2822
mkdir /work
cd /work
apt-get source --download-only --only-source "pipewire=$DEBV"
dscverify --keyring /usr/share/keyrings/debian-keyring.gpg "pipewire_$DEBV.dsc"
mkdir source
python3 - <<'PY'
from pathlib import Path
import os, re, shutil, tarfile
root = Path('/work')
upstream = os.environ['PWV']
archives = list(root.glob(f'pipewire_{upstream}.orig.tar.*'))
assert len(archives) == 1
archive = archives[0]
unpack = root / 'upstream'
unpack.mkdir()
with tarfile.open(archive) as stream:
    stream.extractall(unpack, filter='data')
entries = list(unpack.iterdir())
assert len(entries) == 1 and entries[0].is_dir()
for entry in entries[0].iterdir():
    shutil.move(entry, root / 'source' / entry.name)
shutil.copytree('/recipe/debian', root / 'source/debian')
control = root / 'source/debian/control'
text = control.read_text()
pins = re.findall(r'libspa-0\.2-bluetooth \(= [^)]+\)', text)
named = re.findall(r'AAC codec plugin for PipeWire [0-9][0-9.]*,', text)
assert len(pins) == 1 and len(named) == 1, (pins, named)
text = text.replace(pins[0], f"libspa-0.2-bluetooth (= {os.environ['DEBV']})")
control.write_text(text.replace(named[0], f'AAC codec plugin for PipeWire {upstream},'))
shutil.copy2(archive, root / archive.name.replace('pipewire_', 'pipewire-bluez5-codec-aac_', 1))
shutil.copy2(root / f"pipewire_{os.environ['DEBV']}.dsc",
             root / 'source/debian/upstream-source.dsc')
PY
cd source
if [ "$(dpkg-parsechangelog -S Version)" != "$DEBV+aac2" ]; then
    dch --date "$SOURCE_DATE_RFC2822" --newversion "$DEBV+aac2" --distribution UNRELEASED \
        "Rebuild the AAC plugin against PipeWire $DEBV."
fi
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . "$DEBV+aac2+lc1" --toolkit /toolkit
apt-get -y --no-install-recommends build-dep /work/source
# the link and start gate of lean.debhelper runs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
useradd --create-home --uid 1000 builder
mkdir -p "${SPARKY_LC_SCRATCH:?}"
chown -R builder:builder /work
runuser -u builder -- env SPARKY_LC_ARCHIVE_CONFIG="${SPARKY_LC_ARCHIVE_CONFIG:?}" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
    ${SPARKY_LC_PREVIOUS_DIR:+SPARKY_LC_PREVIOUS_DIR="$SPARKY_LC_PREVIOUS_DIR"} dpkg-buildpackage -us -uc -j4
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
cp .sparky-lc/source.json /out/native-source.json
tar -cJf /out/native-authored-evidence.tar.xz .sparky-lc
cp /work/pipewire-bluez5-codec-aac_*.dsc /work/pipewire-bluez5-codec-aac_*.tar.* \
    /work/*+lc1_*.deb /work/*+lc1_*.buildinfo /work/*+lc1_*.changes /work/*+lc1_*.sparky-build.json /out/
chown -R "$HOSTID" /out
