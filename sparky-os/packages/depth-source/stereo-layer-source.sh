#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the +lc1 source of a stereo-layer release (ORDER 411: 1.13.0-1, which carries the writers of a video's
# 3D layout, stereo_mark_save in libstereo-av) from the release clone: the orig tarball is the clone's `git archive` of the
# release tag without debian/, the Debian part is the clone's debian/ (its changelog names the version), and the Lean Code
# source is prepared with this tree's toolkit, as for the published 1.12.0-4+lc1 (the Qt moc and QML registration read the
# authored headers and sources, so those stay as written). Then build.sh builds it with the link and start gate.
#   stereo-layer-source.sh FORK_CLONE REV OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FORK=$(cd "$1" && pwd)
REV=$2
OUT=$(mkdir -p "$3" && cd "$3" && pwd)
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
docker run --rm -i --name "${SOURCE_NAME:-stereo-layer-source}" --ulimit core=0 --network none --user "$(id -u):$(id -g)" -e HOME=/tmp --cpus "${THREADS:-4}" --platform linux/amd64 -e REV="$REV" --mount type=bind,src="$FORK",dst=/fork,readonly --mount type=bind,src="$OUT",dst=/out --mount type=bind,src="$HERE/../..",dst=/toolkit,readonly \
	--entrypoint bash "${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}" -s <<'INNER'
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
git -C /fork cat-file -e "$REV^{commit}"
git -C /fork show "$REV:debian/changelog" > /tmp/changelog
NEWV=$(dpkg-parsechangelog -l /tmp/changelog -S Version)
UP=${NEWV%-*}
PREFIX=stereo-layer-$UP
W=$(mktemp -d /tmp/stereo-layer-source-XXXXXX)
cd "$W"
mkdir export
git -C /fork archive --format=tar --prefix="$PREFIX/" "$REV" | tar -x -C export
cp -a "export/$PREFIX/debian" debian-export
rm -rf "export/$PREFIX/debian"
stamp=$(git -C /fork log -1 --format=%ct "$REV")
# The source is dated by its release commit, never by the clock (ORDER 421b)
export SOURCE_DATE_EPOCH=$stamp
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$stamp" -C export -cf - "$PREFIX" | xz -9e > "stereo-layer_$UP.orig.tar.xz"
tar -xf "stereo-layer_$UP.orig.tar.xz"
cp -a debian-export "$PREFIX/debian"
cd "$PREFIX"
rm -rf debian/sparky-lean-toolkit
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . "$NEWV+lc1" --toolkit /toolkit \
	--preserve-source 'src/*.h' 'Qt moc and QML type registration consume authored declarations.' \
	--preserve-source 'src/*.cpp' 'Qt moc and QML type registration also scan these sources.'
python3 /toolkit/repo/reproducible.py normalize-tree "$stamp" .
dpkg-buildpackage -S -us -uc -d >/dev/null
cd ..
cp stereo-layer_"$UP".orig.tar.xz stereo-layer_"$NEWV"+lc1.dsc stereo-layer_"$NEWV"+lc1.debian.tar.xz /out/
chown -R 1000:1000 /out
ls -l /out
INNER
