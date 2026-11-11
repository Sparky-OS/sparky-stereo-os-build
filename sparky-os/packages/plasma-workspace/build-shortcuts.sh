#!/bin/bash
# Copyright 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Run as the build user in a container with Debian build dependencies installed.
# WORK is empty scratch; SOURCE holds the published +stereo3d5+lc1 source archives.
# The caller supplies SPARKY_LC_ARCHIVE_CONFIG, SPARKY_LC_SCRATCH and the previous cohort.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
TOOLKIT=$(cd "$HERE/../.." && pwd)
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SOURCE=$(cd "$2" && pwd)
test "$(id -u)" != 0
test -z "$(ls -A "$WORK")"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
cd "$WORK"
cp "$SOURCE/plasma-workspace_6.7.4-2+stereo3d5+lc1.dsc" \
   "$SOURCE/plasma-workspace_6.7.4-2+stereo3d5+lc1.debian.tar.xz" \
   "$SOURCE/plasma-workspace_6.7.4.orig.tar.xz" "$SOURCE/plasma-workspace_6.7.4.orig.tar.xz.asc" .
dpkg-source -x plasma-workspace_6.7.4-2+stereo3d5+lc1.dsc source
python3 "$TOOLKIT/repo/plain-from-lc.py" --save-plan "$WORK/published-preserve.json" source
cd source
cp "$HERE/patches/s6-0001-session-shortcuts-logout-default.patch" debian/patches/
printf '%s\n' s6-0001-session-shortcuts-logout-default.patch >> debian/patches/series
dpkg-source --before-build .
python3 - "$HERE/changelog-stereo3d6.txt" <<'PY'
from pathlib import Path
import os,sys
p=Path('debian/changelog')
p.write_text(Path(sys.argv[1]).read_text().rstrip()+'\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+os.environ['SOURCE_DATE_RFC2822']+'\n\n'+p.read_text())
PY
cd ..
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" source
dpkg-source -b source
cd source
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare "$WORK/source" 4:6.7.4-2+stereo3d6+lc1 --toolkit "$TOOLKIT" --preserve-plan "$WORK/published-preserve.json"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -us -uc -j4
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs "$WORK"/*+lc1_*.deb
