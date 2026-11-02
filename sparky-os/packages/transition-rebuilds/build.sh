#!/bin/bash
# Sparky Stereo OS: rebuilds a published +lc1 source package, unchanged, after a library transition in Debian testing.
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# A package of ours can stop being installable without any change on our side: Debian testing moves a library to a new
# soname, and our build still depends on the old one (sparky-os/repo/check-installable.py finds them; ORDER 317).
# This is the edition's binNMU: the published source, back to its plain form (sparky-os/repo/plain-from-lc.py), one
# changelog entry naming the order and the transition (entries/NAME_VERSION.txt), the Lean Code source
# (lean.debian_prepare), then the build with the link and start gate. Candidates stay in WORK/lc.
# Usage: build.sh WORK SOURCE_DIR DSC PREVIOUS_DIR ENTRY [PLAIN_OPTION]
#   SOURCE_DIR: the folder holding the published +lc1 .dsc and every file it names (checked against the tree's Sources);
#   DSC: that .dsc's file name; PREVIOUS_DIR: the earlier +lc1 .deb files, plus the old library the transition removed
#   (from snapshot.debian.org, checked against that day's signed index), so the predecessor still resolves and the gate
#   compares the new build with it; ENTRY: the changelog entry; PLAIN_OPTION: as plain-from-lc.py documents.
# Settings: SPARKY_PUBLISHED_TREE (the signed published tree, read only: build dependencies and the gate's edition
#   archive), SPARKY_LC_ARCHIVE_DIR (mounted at /archive: sources.json naming the public archives and file:/repo, and the
#   public keyrings it names, sparky-stereo-repo.gpg and deb-multimedia-keyring.gpg among them; see sparky-os/lean/archive.md),
#   SPARKY_BUILD_IMAGE (a debian:testing image updated the same day, with build-essential, devscripts and python3).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${SPARKY_PUBLISHED_TREE:?the signed published tree, read only}"
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate, mounted at /archive}"
: "${SPARKY_BUILD_IMAGE:?a freshly updated debian:testing build image}"
[ $# -ge 5 ] || { sed -n '/^# Usage/,/^# Settings/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
DSC=$3
PREV=$(cd "$4" && pwd)
ENTRY=$(cd "$(dirname "$5")" && pwd)/$(basename "$5")
PLAIN_OPTIONS=${6:-}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
# The .dsc must be the one the signed tree publishes.
python3 - "$SPARKY_PUBLISHED_TREE" "$DSC" >"$WORK/dsc.sha256" <<'PY'
import sys
from pathlib import Path
tree, dsc = sys.argv[1:]
text = (Path(tree) / 'dists/mashtabba/main/source/Sources').read_text()
for stanza in text.split('\n\n'):
    for line in stanza.split('Checksums-Sha256:\n', 1)[-1].splitlines():
        parts = line.split()
        if line.startswith(' ') and len(parts) == 3 and parts[2] == dsc:
            print(parts[0])
            sys.exit(0)
sys.exit('not in the published Sources: ' + dsc)
PY
DSC_SHA256=$(cat "$WORK/dsc.sha256")
docker run --rm --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e DSC="$DSC" -e DSC_SHA256="$DSC_SHA256" -e PLAIN_OPTIONS="$PLAIN_OPTIONS" \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$SPARKY_PUBLISHED_TREE":/repo:ro \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$PREV":/prev:ro -v "$ENTRY":/entry:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	"$SPARKY_BUILD_IMAGE" bash -c 'bash /tools/build-in-container.sh > /work/container.log 2>&1'
