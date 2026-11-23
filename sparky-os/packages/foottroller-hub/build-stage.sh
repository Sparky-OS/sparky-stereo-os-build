#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# The lane launcher supplies the clean recipe commit and the local build inventory.
set -euo pipefail
recipe=$(cd "$(dirname "$0")" && pwd)
toolkit=$(cd "$recipe/../.." && pwd)
output=$(realpath -m "${1:?Usage: build-stage.sh NEW_OUTPUT_DIRECTORY}")
mkdir "$output"
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C TZ=UTC
export ZIG_GLOBAL_CACHE_DIR="$output/zig-cache"
umask 022

artifacts="$output/artifacts"
source_tree="$artifacts/foottroller-hub"
mkdir "$artifacts" "$source_tree"
cp -a "$recipe"/{src,tests,debian,README.md,foottroller-hub.conf,build-stage.sh} "$source_tree/"
dest="$source_tree/debian/sparky-lean-toolkit"
mkdir -p "$dest/lean"
cp "$toolkit"/lean/*.py "$toolkit"/lean/{ZigTokens.zig,JvmLexer.java,smoke.tsv} "$dest/lean/"
cp "$toolkit/repo/provenance.sh" "$dest/"
cp "$toolkit/packages/dpkg-stereo/LICENSE" "$dest/"

export SOURCE_DATE_EPOCH
: "${SOURCE_DATE_EPOCH:?Use the clean committed recipe source date}"
python3 "$toolkit/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "$source_tree"
(
    cd "$source_tree"
    dpkg-buildpackage -S -us -uc
)
cd "$artifacts"
dsc=(foottroller-hub_*.dsc)
dpkg-source -x "${dsc[0]}" extracted
(
    cd extracted
    dpkg-buildpackage -b -us -uc -j4
)
PYTHONPATH="$toolkit" python3 -m lean.release check-debs ./*.deb
sha256sum ./*.deb ./*.dsc ./*.tar.xz ./*.buildinfo ./*.changes ./*.sparky-build.json > SHA256SUMS
sha256sum -c SHA256SUMS
