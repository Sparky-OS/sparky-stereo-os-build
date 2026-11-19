#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
WORK=$1
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
cp -a "$HERE/src" "$WORK/tree"
cd "$WORK/tree"
chmod +x debian/rules
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" 0.1.0+lc1 --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
dpkg-buildpackage -us -uc -sa
