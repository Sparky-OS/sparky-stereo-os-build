#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 17: sparky-stereo-mime-models 20261117.2+lc1, the MIME types of the 3D model, point cloud and splat formats
# that shared-mime-info has not got yet (src/models.xml), a native package of ours through Lean Code.
#   build.sh WORK       (as a user, in a container with debhelper, python3, node-acorn, nodejs, python3-yaml; this tree mounted)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
WORK=$1
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
mkdir "$WORK/tree"
cp -a "$HERE/src/." "$WORK/tree/"
cd "$WORK/tree"
chmod +x debian/rules
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" 20261117.2+lc1 --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
dpkg-buildpackage -us -uc -sa
