#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
# Build kf6-kio's next edition release from its signed published source, keeping
# the source's Lean Code integration, with the patches in ./patches.
# Run as root in a freshly updated Debian testing container whose APT has the
# published edition repository (pin 1001); the build itself runs as UID 1000.
#   SPARKY_PUBLISHED_TREE  the signed repository tree with the predecessor source
#   SPARKY_RELEASE_TOOLKIT the build tree's sparky-os folder (lean.release, translations)
#   SPARKY_LC_PREVIOUS_DIR the predecessor's binary packages (check-link)
#   SPARKY_LC_ARCHIVE_CONFIG the signed public archive sources, SPARKY_LC_SCRATCH the link gate's own state
#                          (lean/archive.md): the source's Lean Code hooks run the link and start gate in
#                          dh_builddeb, and so does check-link below; both need bubblewrap, which runs as the
#                          build user (a container needs --security-opt seccomp=unconfined, apparmor=unconfined and
#                          systempaths=unconfined for its namespaces and /proc) and reaches the public archives; the
#                          source's toolkit 0.1.20 reads no architectures field, so leave out the CUDA source
#   BUILD_ROOT             disposable scratch, OUT the staged result
set -euo pipefail
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): the container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); a missing helper stops the script
sh /run/https-only-apt.sh || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
: "${SPARKY_PUBLISHED_TREE:?}" "${SPARKY_RELEASE_TOOLKIT:?}" "${SPARKY_LC_PREVIOUS_DIR:?}" "${BUILD_ROOT:?}" "${OUT:?}"
: "${SPARKY_LC_ARCHIVE_CONFIG:?}" "${SPARKY_LC_SCRATCH:?}"
# The source is dated by its recipe, never by the clock (ORDER 421b): SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch
# sparky-os/packages/kf6-kio), which the changelog entry, Lean Code and dpkg-source all read.
REPRO=$SPARKY_RELEASE_TOOLKIT/repo/reproducible.py
: "${SOURCE_DATE_EPOCH:?export the recipe date: python3 $SPARKY_RELEASE_TOOLKIT/repo/reproducible.py epoch $HERE}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
PREDECESSOR=6.30.0-1+stereo3d9+lc1
VERSION=6.30.0-1+stereo3d11+lc1
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p "$BUILD_ROOT" "$OUT"
[ ! -e "$BUILD_ROOT/source" ] || { echo "Use a fresh BUILD_ROOT" >&2; exit 2; }
apt-get -y update > "$BUILD_ROOT/prepare-apt.log" 2>&1
apt-get -y --no-install-recommends install quilt >> "$BUILD_ROOT/prepare-apt.log" 2>&1

# The predecessor source exactly as published: every file the .dsc names, checked against the signed index
python3 - "$SPARKY_PUBLISHED_TREE" "$BUILD_ROOT" "$PREDECESSOR" <<'PY'
import hashlib, shutil, sys
from pathlib import Path
tree, work, version = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
for stanza in (tree/'dists/mashtabba/main/source/Sources').read_text().split('\n\n'):
    fields = dict(l.split(': ', 1) for l in stanza.splitlines() if ': ' in l and not l.startswith(' '))
    if fields.get('Package') == 'kf6-kio' and fields.get('Version') == version:
        break
else:
    raise SystemExit(f'kf6-kio {version} is not in the published index')
directory = tree/fields['Directory']
listed = stanza.split('Checksums-Sha256:\n', 1)[1].split('\nFiles:', 1)[0].splitlines()
for line in listed:
    digest, size, name = line.split()
    data = (directory/name).read_bytes()
    assert len(data) == int(size) and hashlib.sha256(data).hexdigest() == digest, name
    shutil.copy2(directory/name, work/name)
PY
cd "$BUILD_ROOT"
dpkg-source -x "kf6-kio_$PREDECESSOR.dsc" source > prepare.log
grep -q sparky-lean-toolkit source/debian/rules || { echo "the predecessor lost its Lean Code hooks" >&2; exit 2; }

# The patches go after the existing series; the changelog entry is written once, here
for patch in "$HERE"/patches/*.patch; do
	name=$(basename "$patch")
	grep -qx "$name" source/debian/patches/series && continue
	cp "$patch" source/debian/patches/
	printf '%s\n' "$name" >> source/debian/patches/series
done
# the translations of the patches' messages, last (sparky-os/translations, README there)
for name in kf6-kio-gpu-launch.po.patch; do
	grep -qx "$name" source/debian/patches/series && continue
	cp "$SPARKY_RELEASE_TOOLKIT/translations/$name" source/debian/patches/
	printf '%s\n' "$name" >> source/debian/patches/series
done
(cd source && QUILT_PATCHES=debian/patches quilt push -a > ../quilt.log)
python3 - source "$VERSION" <<'PY'
import os, sys
from pathlib import Path
source, version = Path(sys.argv[1]), sys.argv[2]
changelog = source/'debian/changelog'
old = changelog.read_text()
entry = (f'kf6-kio ({version}) testing; urgency=medium\n\n'
         '  * Ask the Graphics resolver for paint-env when an entry or its\n'
         '    launch environment already chooses a GPU. Keep that GPU choice\n'
         '    and accept only the three painting variables in this path.\n'
         '  * Require the resolver interface from sparky-stereo-graphics 0.2.9\n'
         '    when the Graphics page is installed (ORDER 518 and 554). Versions\n'
         '    +stereo3d10 and sparky-stereo-graphics 0.2.8 were local candidates\n'
         '    and were never published.\n\n'
         ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n')
changelog.write_text(entry + old)
PY
dpkg-parsechangelog -l source/debian/changelog -S Version | grep -qx "$VERSION"
# The new paint-only query needs the 0.2.9 resolver when it is present (Debian Policy 7.3, Breaks).
python3 - source/debian/control <<'PY'
import sys
from pathlib import Path
control = Path(sys.argv[1])
text = control.read_text()
old = 'Breaks: sparky-stereo-graphics (<< 0.2.4~)'
assert text.count(old) == 1, 'the published KIO Graphics interface constraint changed'
control.write_text(text.replace(old, 'Breaks: sparky-stereo-graphics (<< 0.2.9~)', 1))
PY

apt-get -y update > apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep ./source > build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >> build-dep.log 2>&1
id -u builder > /dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p "$SPARKY_LC_SCRATCH"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" "$BUILD_ROOT/source"
chown -R builder:builder "$BUILD_ROOT" "$SPARKY_LC_SCRATCH"
cd source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR="$SPARKY_LC_PREVIOUS_DIR" SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" \
	SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" DEBFULLNAME="$DEBFULLNAME" DEBEMAIL="$DEBEMAIL" \
	dpkg-buildpackage -us -uc -F -j4 > ../build.log 2>&1
cd ..
PYTHONPATH="$SPARKY_RELEASE_TOOLKIT" python3 -m lean.release check-debs ./*.deb > check-debs.log 2>&1
runuser -u builder -- env PYTHONPATH="$SPARKY_RELEASE_TOOLKIT" SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
	python3 -m lean.release check-link --previous-dir "$SPARKY_LC_PREVIOUS_DIR" ./*.deb > check-link.log 2>&1
cp ./*.deb ./*.changes ./*.buildinfo "kf6-kio_$VERSION.dsc" "kf6-kio_$VERSION.debian.tar.xz" kf6-kio_6.30.0.orig.tar.xz* "$OUT/"
(cd "$OUT" && sha256sum -- *.deb *.dsc *.tar.* *.changes *.buildinfo > SHA256SUMS)
chown -R 1000:1000 "$BUILD_ROOT" "$OUT"
echo "kf6-kio $VERSION staged in $OUT"
