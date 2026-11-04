#!/bin/bash
# Sparky Stereo OS: rebuilds a published +lc1 source package with the edition's translation patch added to its series.
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# The edition's translated strings live in sparky-os/translations/*.po.patch and reach a person only through a package whose
# debian/patches/series names the patch (dpkg-source(1): the series "lists all patches that have to be applied"; a patch no
# series names never ships). Six of them were never named by any build (ORDER 391). This is the build that names one:
# the published source back to its plain form (sparky-os/repo/plain-from-lc.py), the patch last in the series, one changelog
# entry (entries/NAME_VERSION.txt), the Lean Code source (lean.debian_prepare), then the build with the link and start gate.
# No code, default or dependency changes. Candidates stay in WORK/lc.
# Usage: build.sh WORK SOURCE_DIR DSC PREVIOUS_DIR ENTRY PATCH [PLAIN_OPTION]
#   SOURCE_DIR: the folder holding the published +lc1 .dsc and every file it names; DSC: that .dsc's file name; its checksum
#   comes from SHA256SUMS in SOURCE_DIR when that lists it, else from the signed tree's Sources; PREVIOUS_DIR: the earlier
#   +lc1 .deb files, for the link gate's predecessor; ENTRY: the changelog entry; PATCH: the file name in sparky-os/translations;
#   PLAIN_OPTION: as plain-from-lc.py documents.
# Optional environment: CODE_PATCH (a path under sparky-os, the code half, put before the translations in the series),
#   CONTROL_PACKAGE, CONTROL_FIELD (Depends or Recommends) and CONTROL_ADD (a package added first to that field of that binary
#   package: the dependency the code half needs).
# Settings: SPARKY_PUBLISHED_TREE (the signed published tree, read only), SPARKY_LC_ARCHIVE_DIR (mounted at /archive:
#   sources.json and the public keyrings it names; see sparky-os/lean/archive.md), SPARKY_BUILD_IMAGE (a debian:testing image
#   with build-essential, devscripts and python3).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${SPARKY_PUBLISHED_TREE:?the signed published tree, read only}"
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate, mounted at /archive}"
: "${SPARKY_BUILD_IMAGE:?a debian:testing build image}"
[ $# -ge 6 ] || { sed -n '/^# Usage/,/^# Settings/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
DSC=$3
PREV=$(cd "$4" && pwd)
ENTRY=$(cd "$(dirname "$5")" && pwd)/$(basename "$5")
PATCH=$6
PLAIN_OPTIONS=${7:-}
[ -f "$HERE/../../translations/$PATCH" ] || { echo "no sparky-os/translations/$PATCH" >&2; exit 1; }
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
python3 - "$SPARKY_PUBLISHED_TREE" "$SRC" "$DSC" >"$WORK/dsc.sha256" <<'PY'
import sys
from pathlib import Path
tree, src, dsc = sys.argv[1:]
sums = Path(src) / 'SHA256SUMS'
if sums.is_file():
    for line in sums.read_text().splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].lstrip('*') == dsc:
            print(parts[0])
            sys.exit(0)
text = (Path(tree) / 'dists/mashtabba/main/source/Sources').read_text()
for stanza in text.split('\n\n'):
    for line in stanza.split('Checksums-Sha256:\n', 1)[-1].splitlines():
        parts = line.split()
        if line.startswith(' ') and len(parts) == 3 and parts[2] == dsc:
            print(parts[0])
            sys.exit(0)
sys.exit('not in SHA256SUMS or the published Sources: ' + dsc)
PY
DSC_SHA256=$(cat "$WORK/dsc.sha256")
docker run --rm --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e DSC="$DSC" -e DSC_SHA256="$DSC_SHA256" -e PLAIN_OPTIONS="$PLAIN_OPTIONS" -e PATCH="$PATCH" -e CODE_PATCH="${CODE_PATCH:-}" -e CONTROL_PACKAGE="${CONTROL_PACKAGE:-}" -e CONTROL_FIELD="${CONTROL_FIELD:-}" -e CONTROL_ADD="${CONTROL_ADD:-}" \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$SPARKY_PUBLISHED_TREE":/repo:ro \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$PREV":/prev:ro -v "$ENTRY":/entry:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	"$SPARKY_BUILD_IMAGE" bash -c 'bash /tools/build-in-container.sh > /work/container.log 2>&1'
