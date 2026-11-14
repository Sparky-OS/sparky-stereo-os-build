#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 551: the +lc1 source of kf6-kimageformats 6.30.0-1+stereo3d7 (ORDER 526's JPS descriptor
# writer and shared JPEG codec, ../jps-descriptor) from the published +stereo3d5+lc1 source: that recipe's
# prepare-source.py gives the plain +stereo3d7, and Lean Code prepares it with this tree's toolkit. Runs inside the Lean
# Code migration container (round.sh starts it): /in holds the published source set, /toolkit is sparky-os, /out receives
# the new .dsc, the Debian tarball and the orig tarball.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
RECIPE=/toolkit/packages/jps-descriptor
# the date of this source is its recipe's (ORDER 421b)
: "${SOURCE_DATE_EPOCH:?the date of the jps-descriptor recipe (repo/reproducible.py epoch)}"
export SOURCE_DATE_EPOCH
W=$(mktemp -d /tmp/kimageformats-source-XXXXXX)
cp /in/kf6-kimageformats_6.30.0-1+stereo3d5+lc1.dsc /in/kf6-kimageformats_6.30.0-1+stereo3d5+lc1.debian.tar.xz /in/kf6-kimageformats_6.30.0.orig.tar.xz "$W/"
cd "$W"
dpkg-source -x kf6-kimageformats_6.30.0-1+stereo3d5+lc1.dsc source >/dev/null
python3 "$RECIPE/prepare-source.py" "$W/source"
cd source
[ "$(dpkg-parsechangelog -S Version)" = 6.30.0-1+stereo3d7 ] || { echo "prepare-source.py gave $(dpkg-parsechangelog -S Version)" >&2; exit 1; }
# the published baseline carries no source-consumer plan (the recipe's README); a plan left beside the source would be handed back here
[ ! -e "$W/source.preserve.json" ] || { echo "a preserve plan was carried: pass it with --preserve-plan" >&2; exit 1; }
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 6.30.0-1+stereo3d7+lc1 --toolkit /toolkit
python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -S -us -uc -d >/dev/null
cd ..
cp kf6-kimageformats_6.30.0.orig.tar.xz kf6-kimageformats_6.30.0-1+stereo3d7+lc1.dsc kf6-kimageformats_6.30.0-1+stereo3d7+lc1.debian.tar.xz /out/
chown -R 1000:1000 /out
ls -l /out
