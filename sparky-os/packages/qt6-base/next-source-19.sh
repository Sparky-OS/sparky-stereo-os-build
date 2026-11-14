#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qt6-base, +stereo3d19 (ORDER 518 and 554, Widgets painted on the graphics card):
# the published +stereo3d16+lc1 source unpacked, the painting patches appended to its series, the three baked shaders under
# debian/painting-shaders (a quilt patch cannot carry them; debian/source/include-binaries lists them), the manifest of the
# patches that are ours, and the changelog entry of the plain version then the Lean Code entry on top of the published
# history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte identical suffix.
# +stereo3d17 and +stereo3d18 were a lane's local candidates on +stereo3d15 and were never published; their numbers are
# not used again, so that one version names one set of bytes.
#   next-source-19.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the published +stereo3d16+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
# Run it twice into two folders: the .dsc and the Debian tarball must hash the same. The date is this folder's last commit.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '6.11.2+dfsg-5+stereo3d16+lc1' ] || { echo "the published source must be 6.11.2+dfsg-5+stereo3d16+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/qt6-base-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches" "$W/overlay/painting-shaders" "$W/overlay/source"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in "$HERE"/painting-patches/o518-*.patch "$HERE"/painting-patches/o554-*.patch; do
	name=$(basename "$p")
	if grep -qxF "$name" "$W/published/debian/patches/series"; then echo "$name is already in the published series" >&2; exit 2; fi
	cp "$p" "$W/overlay/patches/"
	echo "$name" >> "$W/overlay/patches/series"
done
# the baked shaders, checked, where o554-0001 takes them from
(cd "$HERE/painting-shaders" && sha256sum -c --quiet SHA256SUMS)
[ ! -e "$W/published/debian/source/include-binaries" ] || cp "$W/published/debian/source/include-binaries" "$W/overlay/source/include-binaries"
for shader in "$HERE"/painting-shaders/*.qsb; do
	cp "$shader" "$W/overlay/painting-shaders/"
	echo "debian/painting-shaders/$(basename "$shader")" >> "$W/overlay/source/include-binaries"
done
# the symbols the painting exports, at this version without its Lean Code part and with "~" (a symbols file with the
# whole current version is a lintian error, and a lower version would let a Qt without the painting satisfy a user)
for add in "$HERE"/painting-symbols/*.symbols.add; do
	name=$(basename "$add" .add)
	[ -z "$(tail -c1 "$W/published/debian/$name")" ] || { echo "$name does not end with a newline" >&2; exit 2; }
	cat "$W/published/debian/$name" "$add" > "$W/overlay/$name"
done
# the patches that are ours, for the copyright file (repo/provenance-files.py reads each patch's own header)
[ ! -e "$W/published/debian/sparky-provenance-files" ] || { echo "the published source has a provenance manifest: merge it here" >&2; exit 2; }
mkdir -p "$W/ours/debian/patches"
cp "$W/overlay/patches"/o5*.patch "$W/ours/debian/patches/"
python3 "$REPO/provenance-files.py" "$W/ours" 'o518-*.patch' 'o554-*.patch' >/dev/null
cp "$W/ours/debian/sparky-provenance-files" "$W/overlay/sparky-provenance-files"
mapfile -t items < <(python3 - "$HERE/changelog/stereo3d19.items" <<'PY'
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 6.11.2+dfsg-5+stereo3d19 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
