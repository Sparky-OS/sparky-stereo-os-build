#!/bin/bash
# In the mdmo-mpvbuild:2 container, as the user: build the mpv-dmo source with our patches.
set -eu
export HOME=/tmp/home; mkdir -p $HOME
export DEB_BUILD_OPTIONS="nocheck parallel=4"
export LC_ALL=C.UTF-8
cd /w/build-mpv/mpv-dmo-0.41.0
date -u +"build start %F %T"
QUILT_PATCHES=debian/patches quilt --quiltrc=/dev/null push -a 2>&1 | grep -E "Hunk|offset|fuzz|FAILED|rejects|Now at" | head -20 || true
QUILT_PATCHES=debian/patches quilt --quiltrc=/dev/null pop -a 2>&1 | tail -1 || true
nice -n 10 dpkg-buildpackage -b -us -uc 2>&1
date -u +"build end %F %T"
