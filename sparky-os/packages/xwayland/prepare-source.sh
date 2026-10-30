#!/bin/bash
# Extend the published source package, keeping its complete patch and LC pipeline.
set -euo pipefail
source_dir=${1:?directory containing the published +stereo3d3+lc1 source package}
work=${2:?empty output directory}
recipe=$(cd "$(dirname "$0")" && pwd)
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p "$work"
test -z "$(ls -A "$work")"
source_dir=$(cd "$source_dir" && pwd)
work=$(cd "$work" && pwd)
cd "$work"
echo '59654b65ca60baa722edea256d05b776658a4b769914eb17441c07a2337015c4  '"$source_dir/xwayland_24.1.13-1+stereo3d3+lc1.dsc" | sha256sum -c
cp "$source_dir/xwayland_24.1.13.orig.tar.xz" .
dpkg-source -x "$source_dir/xwayland_24.1.13-1+stereo3d3+lc1.dsc" source
patch=0009-preserve-stereo-pairs-across-child-redirection.patch
cp "$recipe/patches/$patch" source/debian/patches/
printf '%s\n' "$patch" >> source/debian/patches/series
cd source
dch --newversion '2:24.1.13-1+stereo3d4' --distribution unstable \
    'Preserve both stereo child views across first-copy presentation, compositor redirection and backing-pixmap recycling; keep declaration ownership in Mesa.'
dch --newversion '2:24.1.13-1+stereo3d4+lc1' --distribution UNRELEASED \
    'Retain the published source and payload Lean Code pipeline with provenance before sealing.'
dpkg-source --before-build .
cd ..
dpkg-source -b source
