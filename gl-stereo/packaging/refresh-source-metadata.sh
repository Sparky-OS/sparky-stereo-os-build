#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
# Regenerate a clean source snapshot after metadata-only corrections, while
# preserving the original build tree and its compiled objects.
name=${1:?source name}
case "$name" in
    plasma-desktop) version=6.7.4-1; tree=plasma-desktop-6.7.4 ;;
    *) exit 2 ;;
esac
work=/build/source-refresh
mkdir -p "$work"
cd "$work"
cp /workspace/gl-stereo/out/packages/sources/"$name"_* .
dpkg-source --no-check -x "$name"_"$version".dsc
cp /build/sources/"$tree"/debian/{control,copyright,changelog} "$tree/debian/"
cp /build/sources/"$tree"/debian/patches/stereo-show.patch "$tree/debian/patches/"
printf '\nstereo-show.patch\n' >>"$tree/debian/patches/series"
dpkg-source --before-build "$tree"
dpkg-source -b "$tree"
cp "$name"_"$version"+stereo3d1.{dsc,debian.tar.xz} /build/sources/
