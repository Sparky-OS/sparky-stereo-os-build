#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Build kf6-kio's next edition release from its signed published source, keeping
# the source's Lean Code integration, with the patches in ./patches.
# Run as root in a freshly updated Debian testing container whose APT has the
# published edition repository (pin 1001); the build itself runs as UID 1000.
#   SPARKY_PUBLISHED_TREE  the signed repository tree with the predecessor source
#   SPARKY_RELEASE_TOOLKIT the build tree's sparky-os folder (lean.release)
#   SPARKY_LC_PREVIOUS_DIR the predecessor's binary packages (check-link)
#   BUILD_ROOT             disposable scratch, OUT the staged result
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${SPARKY_PUBLISHED_TREE:?}" "${SPARKY_RELEASE_TOOLKIT:?}" "${SPARKY_LC_PREVIOUS_DIR:?}" "${BUILD_ROOT:?}" "${OUT:?}"
PREDECESSOR=6.30.0-1+stereo3d5+lc1
VERSION=6.30.0-1+stereo3d6+lc1
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p "$BUILD_ROOT" "$OUT"
[ ! -e "$BUILD_ROOT/source" ] || { echo "Use a fresh BUILD_ROOT" >&2; exit 2; }

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
(cd source && QUILT_PATCHES=debian/patches quilt push -a > ../quilt.log)
python3 - source "$VERSION" <<'PY'
import email.utils, sys
from pathlib import Path
source, version = Path(sys.argv[1]), sys.argv[2]
changelog = source/'debian/changelog'
old = changelog.read_text()
entry = (f'kf6-kio ({version}) testing; urgency=medium\n\n'
         '  * Start an application whose desktop entry does not say where it runs on\n'
         '    the GPU the Graphics page chooses for its kind (sparky-stereo-gpu-env\n'
         '    --app): players on the GPU measured best, battery included, games and\n'
         '    other programs in 2D by the power profile. PrefersNonDefaultGPU and a\n'
         '    GPU chosen in the launch environment keep their precedence; without\n'
         '    the command the launch is unchanged.\n\n'
         ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n')
changelog.write_text(entry + old)
PY
dpkg-parsechangelog -l source/debian/changelog -S Version | grep -qx "$VERSION"

apt-get -y update > apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep ./source > build-dep.log 2>&1
id -u builder > /dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder "$BUILD_ROOT"
cd source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR="$SPARKY_LC_PREVIOUS_DIR" DEBFULLNAME="$DEBFULLNAME" DEBEMAIL="$DEBEMAIL" \
	dpkg-buildpackage -us -uc -F -j4 > ../build.log 2>&1
cd ..
PYTHONPATH="$SPARKY_RELEASE_TOOLKIT" python3 -m lean.release check-debs ./*.deb > check-debs.log 2>&1
PYTHONPATH="$SPARKY_RELEASE_TOOLKIT" python3 -m lean.release check-link --previous-dir "$SPARKY_LC_PREVIOUS_DIR" ./*.deb > check-link.log 2>&1
cp ./*.deb ./*.changes ./*.buildinfo "kf6-kio_$VERSION.dsc" "kf6-kio_$VERSION.debian.tar.xz" kf6-kio_6.30.0.orig.tar.xz* "$OUT/"
(cd "$OUT" && sha256sum -- *.deb *.dsc *.tar.* *.changes *.buildinfo > SHA256SUMS)
chown -R 1000:1000 "$BUILD_ROOT" "$OUT"
echo "kf6-kio $VERSION staged in $OUT"
