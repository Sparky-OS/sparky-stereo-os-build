#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" != 0
repo=$PWD
cd out/packages/sources
for source in *.dsc; do
    directory=$(sed -n 's/^Source: //p' "$source")
    version=$(sed -n 's/^Version: //p' "$source")
    version=${version#*:}; version=${version%-*}
    if [ ! -d "$directory-$version" ]; then dpkg-source --no-check -x "$source"; fi
done
patch --dry-run -p1 -d kscreenlocker-6.7.4 < "$repo/plasma/patches/kscreenlocker-stereo-background.patch"
patch --dry-run -p1 -d plasma-desktop-6.7.4 < "$repo/plasma/patches/plasma-desktop-stereo-background.patch"
patch --dry-run -p1 -d xscreensaver-6.09+dfsg1 < "$repo/savers/rocks-sbs.patch"
