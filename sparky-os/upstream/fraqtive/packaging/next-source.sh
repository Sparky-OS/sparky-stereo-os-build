#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 743: the +lc1 source of fraqtive 0.4.8.1-1+stereo3d3, made from Debian's own 0.4.8.1-1 source.
# Runs as root inside the Lean Code migration container (build.sh starts it, with the https-only apt helper and the host's CA
# bundle mounted). Debian's source is fetched here, from Debian's signed index (apt-get source), and refused unless its three
# files have the SHA-256 recorded below (read from the same index on 2026-11-19); the two patches of ../patches go last in its
# series; one changelog entry says why; then the Lean Code preparation (lean.debian_prepare) and the packed +lc1 source.
# Usage: next-source.sh OUT      (environment: SOURCE_DATE_EPOCH, SOURCE_DATE_RFC2822, and /toolkit = the build tree's sparky-os,
#   /recipe = this folder's parent)
#   OUT receives the +lc1 .dsc, its Debian tarball and the orig tarball, and plain/ with the same source before Lean Code.
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?the date of this source belongs to its recipe, never to the clock}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
OUT=$1
[ -z "$(ls -A "$OUT" 2>/dev/null)" ] || { echo "$OUT is not empty" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
UPSTREAM=0.4.8.1 DEBIAN=0.4.8.1-1 VERSION=0.4.8.1-1+stereo3d3
mkdir -p "$OUT/plain" "$OUT/fetch"
printf 'Types: deb-src\nURIs: https://deb.debian.org/debian\nSuites: testing\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n' > /etc/apt/sources.list.d/fq743-src.sources
apt-get -qq update --error-on=any
cd "$OUT/fetch"
apt-get source --download-only "fraqtive=$DEBIAN" >/dev/null
sha256sum -c <<SUMS
5df9ff24101bd39ba406f56944629795f1d7ae05d984e7f07ea8b1f17739d974  fraqtive_$DEBIAN.dsc
9ef746892287a743ac40004607842bc192218f5810fe5e220cf2d12ba38964f6  fraqtive_$DEBIAN.debian.tar.xz
f3e152e15072f6cbecf100d748f21e4e7a48eace77b93d7daf837ea86491b46b  fraqtive_$UPSTREAM.orig.tar.gz
SUMS
cp fraqtive_$DEBIAN.dsc fraqtive_$DEBIAN.debian.tar.xz fraqtive_$UPSTREAM.orig.tar.gz ../plain/
cd ../plain
# the patches are added to an unapplied tree: no .pc directory, so dpkg-source applies them itself when it packs
dpkg-source --skip-patches -x fraqtive_$DEBIAN.dsc t >/dev/null
cp /recipe/patches/0001-*.patch t/debian/patches/03-vertex-arrays-with-current-context.diff
cp /recipe/patches/0002-*.patch t/debian/patches/04-qopenglwidget-for-wayland.diff
cp /recipe/patches/0003-*.patch t/debian/patches/05-port-to-qt6.diff
cp /recipe/patches/0004-*.patch t/debian/patches/06-3d-view-stereo-area.diff
cp /recipe/patches/0005-*.patch t/debian/patches/07-3d-options-sentences-languages.diff
[ -z "$(tail -c1 t/debian/patches/series)" ] || echo >> t/debian/patches/series
printf '%s\n' 03-vertex-arrays-with-current-context.diff 04-qopenglwidget-for-wayland.diff 05-port-to-qt6.diff 06-3d-view-stereo-area.diff 07-3d-options-sentences-languages.diff >> t/debian/patches/series
# the build on Qt 6: Build-Depends and the configure line (debian/ is not patched through the series)
(cd t && patch -s -p1 < /recipe/packaging/debian-qt6.patch)
python3 - "$VERSION" "$SOURCE_DATE_RFC2822" <<'PY'
import sys
from pathlib import Path
version, date = sys.argv[1:]
entry = Path('/recipe/packaging/changelog/fraqtive.entry').read_text().replace('@VERSION@', version)
p = Path('t/debian/changelog')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + date + '\n\n' + p.read_text())
PY
(cd t && dpkg-source --before-build . && dpkg-source --after-build .)
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
[ -f fraqtive_$VERSION.dsc ]
# the Lean Code source: the same tree, prepared by the toolkit, packed next to the same orig tarball
mkdir -p ../lc
cp fraqtive_$VERSION.dsc fraqtive_$VERSION.debian.tar.xz fraqtive_$UPSTREAM.orig.tar.gz ../lc/
cd ../lc
dpkg-source -x fraqtive_$VERSION.dsc t >/dev/null
PYTHONPATH=/toolkit python3 -m lean.debian_prepare t "$VERSION+lc1" --toolkit /toolkit
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
rm -f fraqtive_$VERSION.dsc fraqtive_$VERSION.debian.tar.xz
dpkg-source -b t >/dev/null
rm -rf t
ls
cp fraqtive_$VERSION+lc1.dsc fraqtive_$VERSION+lc1.debian.tar.xz fraqtive_$UPSTREAM.orig.tar.gz "$OUT/"
rm -rf "$OUT/fetch"
chown -R 1000:1000 "$OUT"
