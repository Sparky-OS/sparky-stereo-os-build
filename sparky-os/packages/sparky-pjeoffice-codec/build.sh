#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# FFmpeg 5.1.10 as released: fetched from ffmpeg.org, checked against the pinned SHA-256 and the release key's signature, then built
# as a conventional debhelper source with the edition's Lean Code stages (the upstream source keeps its own bytes).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
PACKAGE=sparky-pjeoffice-codec
VERSION=5.1.10
TARBALL=ffmpeg-$VERSION.tar.xz
SHA256=392306d6fc45dab0e9e0ea55381e071842e83a2fb31d320aeda40477a7766293
KEY=FCF986EA15E6E293A5644F10B4322F04D67658D8
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:?the host passes the date of the recipe: build-provenance.sh}
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Ramos (Capitain Jack)"
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.codec.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
curl --fail --silent --show-error --proto '=https' --proto-redir '=https' -o "$TARBALL" "https://ffmpeg.org/releases/$TARBALL"
curl --fail --silent --show-error --proto '=https' --proto-redir '=https' -o "$TARBALL.asc" "https://ffmpeg.org/releases/$TARBALL.asc"
curl --fail --silent --show-error --proto '=https' --proto-redir '=https' -o ffmpeg-devel.asc "https://ffmpeg.org/ffmpeg-devel.asc"
[ "$(sha256sum "$TARBALL" | cut -d' ' -f1)" = "$SHA256" ] || { echo "$TARBALL does not match the pinned SHA-256 $SHA256" >&2; exit 1; }
export GNUPGHOME=$WORK/gnupg; mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --import ffmpeg-devel.asc 2>/dev/null
gpg --batch --status-fd 1 --verify "$TARBALL.asc" "$TARBALL" 2>/dev/null | grep -q "^\[GNUPG:\] VALIDSIG $KEY " ||
	gpg --batch --status-fd 1 --verify "$TARBALL.asc" "$TARBALL" 2>/dev/null | grep "^\[GNUPG:\] VALIDSIG" | grep -q "$KEY" ||
	{ echo "the signature of $TARBALL is not valid for the release key $KEY" >&2; exit 1; }
echo "verified: $TARBALL sha256 $SHA256, signed by $KEY"
# the orig tarball is upstream's file, byte for byte, named for this source package
cp "$TARBALL" "${PACKAGE}_$VERSION.orig.tar.xz"
SRC=$WORK/source   # not named package-version: dch renames a folder that is
mkdir "$SRC" && tar -xf "$TARBALL" -C "$SRC" --strip-components=1
python3 "$TOOLKIT/../tools/copy-recipe.py" "$HERE/debian" "$SRC/debian"
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "$SRC/debian"
(cd "$SRC" && PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . "$VERSION+lc1" \
	--preserve-source '*' 'FFmpeg is the signed upstream release, unmodified: it keeps its own bytes (its comments are its licence notices and documentation)')
(cd "$SRC" && PYTHONPATH="$TOOLKIT" JOBS="${JOBS:-4}" dpkg-buildpackage -us -uc -sa -j"${JOBS:-4}" >"$WORK/build.log" 2>&1) || { tail -40 "$WORK/build.log"; exit 1; }
cp "$WORK"/*.deb "$WORK"/*.dsc "$WORK"/*.tar.xz "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK"/*.json "$OUT/" 2>/dev/null || true
cp "$WORK/build.log" "$OUT/build.log"
(cd "$OUT" && PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*.deb)
