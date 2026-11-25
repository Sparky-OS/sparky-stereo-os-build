#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, queue row 81 part D: the next source of kpipewire, whose encoded stream can keep a constant frame rate on
# a still source (a Cast receiver's player waits for the next picture of a live stream).
# It follows kpipewire 6.7.4-1+stereo3d9, ORDER 740's successor (HEVC stereo packing, ../kpipewire-740 on branch order740;
# staged and accepted, not yet published), so the two changes travel in one line of versions and neither drops the other:
# that source unpacked; this folder's patch appended to its series; the two new symbols added to libkpipewirerecord6.symbols
# at the version that brings them; the patch named in debian/sparky-provenance-files beside ORDER 740's; and the plain entry
# on top of its history (repo/lc-successor.py --in-place --overlay --reapply-patches).
# Its versions carry no +lc1 (the 19 October adapter's shape, debian/sparky-lean; the Lean Code mark is in the packages'
# fields), and lc-successor keeps that shape, so the next version is NEXT itself. The toolkit in debian/sparky-lean becomes
# this tree's: the published +stereo3d8 still carries the 19 October copy, whose link gate refuses a root floor under 12 GiB,
# while build main's floor is 1 GiB (ORDER 638).
#   next-source.sh BASE_DIR OUT
#   BASE_DIR: the folder with kpipewire_6.7.4-1+stereo3d9.dsc, its Debian tarball and the orig tarball. The .dsc must be the
#   one ORDER 740 staged (its SHA-256 below); dpkg-source checks the files it names.
# Run it where dpkg-source and quilt are (the Lean Code migration image: build.sh does).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
BASE=$(cd "${1:?usage: next-source.sh BASE_DIR OUT}" && pwd)
OUT=${2:?usage: next-source.sh BASE_DIR OUT}
BASE_DSC=$BASE/kpipewire_6.7.4-1+stereo3d9.dsc
# ORDER 740's staged source (/mnt/build/flat-headset-hevc-740/stage/SHA256SUMS, 2026-11-19), and nothing else
printf '%s  %s\n' 47c65e0d238daf38664f2877734aaf3bc8d05794c98ed072d7b6ea0b3239ffe5 "$BASE_DSC" | sha256sum --quiet -c
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
NEXT=6.7.4-1+stereo3d10
W=$(mktemp -d "${TMPDIR:-/tmp}/kpipewire-81d-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$BASE_DSC" "$W/base" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/base/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | od -An -tx1 | tr -d ' ')" = 0a ] || echo >> "$W/overlay/patches/series"
cp "$HERE/patches/kpipewire-constant-framerate.patch" "$W/overlay/patches/"
echo kpipewire-constant-framerate.patch >> "$W/overlay/patches/series"
# the two symbols the patch adds, at the version that brings them (the edition's own symbols are kept this way)
cp "$W/base/debian/libkpipewirerecord6.symbols" "$W/overlay/libkpipewirerecord6.symbols"
printf ' _ZN25PipeWireBaseEncodedStream20setConstantFramerateEb@Base %s\n _ZNK25PipeWireBaseEncodedStream17constantFramerateEv@Base %s\n' \
    "$NEXT" "$NEXT" >> "$W/overlay/libkpipewirerecord6.symbols"
# the files of debian/ that are ours (repo/provenance.sh reads it for the copyright file): ORDER 740's lines and this patch
cp "$W/base/debian/sparky-provenance-files" "$W/overlay/sparky-provenance-files"
echo 'debian/patches/kpipewire-constant-framerate.patch' >> "$W/overlay/sparky-provenance-files"
mapfile -t items < <(python3 - "$HERE/changelog/kpipewire.items" <<'PY'
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --reapply-patches --next "$NEXT" "${args[@]}" --overlay "$W/overlay" \
    --source-date-epoch "$SOURCE_DATE_EPOCH" --work "$W" "$BASE_DSC" "$OUT"
