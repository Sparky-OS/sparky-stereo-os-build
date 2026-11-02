#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/source.env"
SOURCE=${1:?Usage: prepare-source.sh VERIFIED_CLONE NEW_OUTPUT_DIRECTORY}
OUT=${2:?Usage: prepare-source.sh VERIFIED_CLONE NEW_OUTPUT_DIRECTORY}
"$HERE/fetch-source.sh" --verify "$SOURCE"
if [ -e "$OUT" ] || [ -L "$OUT" ]; then
	printf 'cgm-zig: output already exists: %s\n' "$OUT" >&2
	exit 1
fi
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export SOURCE_DATE_EPOCH=$(git -C "$SOURCE" show -s --format=%ct "$CGM_ZIG_COMMIT")
TREE=$OUT/cgm-zig-$CGM_ZIG_VERSION
git -C "$SOURCE" archive --format=tar --prefix="cgm-zig-$CGM_ZIG_VERSION/" "$CGM_ZIG_COMMIT" | xz -T1 > "$OUT/cgm-zig_${CGM_ZIG_VERSION}.orig.tar.xz"
tar -xf "$OUT/cgm-zig_${CGM_ZIG_VERSION}.orig.tar.xz" -C "$OUT"
cp -a "$HERE/debian" "$TREE/"
mkdir "$TREE/debian/cgm"
cp "$HERE/"{configure.sh,check-stage3-command.py,source.env,ATTRIBUTIONS.md} "$TREE/debian/cgm/"
cp -a "$HERE/tests" "$TREE/debian/cgm/"
# The source archive carries the exact toolkit that qualifies its build and payload.
PYTHONPATH="$HERE/../.." python3 -m lean.debian_prepare "$TREE" "$CGM_ZIG_VERSION-1+lc1" --toolkit "$HERE/../.." \
	--preserve-source 'test/*' 'Compiler tests contain deliberate syntax, comments and directive fixtures; retain upstream test inputs verbatim'
(cd "$TREE" && dpkg-source -b .)
