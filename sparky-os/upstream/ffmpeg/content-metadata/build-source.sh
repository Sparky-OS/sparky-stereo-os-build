#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DEBEMAIL=Capitain_Jack@yahoo.com
export DEBFULLNAME='Daniel Ramos (Capitain Jack)'
input=${1:?published source package directory}
work=${2:?new source output directory}
recipe=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$work"
cp "$input/ffmpeg-dmo_9.0.2.orig.tar.xz" "$work/"
dpkg-source -x "$input/ffmpeg-dmo_9.0.2-dmo1+stereo3d6+lc1.dsc" "$work/source"
cd "$work/source"
cp "$recipe/retain-st3d-with-vexu.patch" debian/patches/0053-avformat-mov-retain-st3d-with-vexu.patch
cp "$recipe/fate-stereo-metadata.patch" debian/patches/0054-fate-mov-stereo-metadata.patch
printf '%s\n' 0053-avformat-mov-retain-st3d-with-vexu.patch 0054-fate-mov-stereo-metadata.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a
dch --newversion '10:9.0.2-dmo1+stereo3d7+lc1' --distribution unstable 'Preserve st3d packing and right-first/custom modes when merging vexu eye metadata, with generated FATE regression coverage.'
# Retain the published native projection, restore and qualified payload hooks.
dpkg-buildpackage -S -us -uc -d
