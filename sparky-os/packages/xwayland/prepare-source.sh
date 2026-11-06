#!/bin/bash
# Extend the published source package, keeping its complete patch and LC pipeline.
set -euo pipefail
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
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
dch --date "$SOURCE_DATE_RFC2822" --newversion '2:24.1.13-1+stereo3d4' --distribution unstable \
    'Preserve both stereo child views across first-copy presentation, compositor redirection and backing-pixmap recycling; keep declaration ownership in Mesa.'
dch --date "$SOURCE_DATE_RFC2822" --newversion '2:24.1.13-1+stereo3d4+lc1' --distribution UNRELEASED \
    'Retain the published source and payload Lean Code pipeline with provenance before sealing.'
dpkg-source --before-build .
cd ..
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" source
dpkg-source -b source
