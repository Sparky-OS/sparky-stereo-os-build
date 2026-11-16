#!/bin/bash
# Sparky Stereo OS: the next +lc1 sources of Dragon Player and Haruna, each the published source with one patch more
# (ORDER 586: the 3D switch reads "Ativar 3D" in Brazilian Portuguese), made with repo/lc-successor.py --in-place --overlay.
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Usage: mk-successors.sh OUT PUBLISHED_POOL
#   OUT: receives one folder per source (the new .dsc and Debian tarball); PUBLISHED_POOL: the repository's pool/main folder.
set -euo pipefail
# the sources are the same bytes under any umask: extraction by tar and dpkg-source follows it, so the recipe fixes it
umask 022
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
POOL=${2:?}
EPOCH=$(python3 "$TREE/sparky-os/repo/reproducible.py" epoch "$HERE")
export SOURCE_DATE_EPOCH=$EPOCH
one() { # NAME DSC NEXT PATCHFILE PATCHNAME ITEM
	local name=$1 dsc=$2 next=$3 patch=$4 pname=$5 item=$6
	local work; work=$(mktemp -d "$OUT/.work.XXXXXX")
	dpkg-source -x --no-check "$dsc" "$work/old" >/dev/null
	mkdir -p "$work/overlay/patches"
	cp "$HERE/patches/$patch" "$work/overlay/patches/$pname"
	{ cat "$work/old/debian/patches/series"; echo "$pname"; } > "$work/overlay/patches/series"
	mkdir -p "$OUT/$name"
	python3 "$TREE/sparky-os/repo/lc-successor.py" --in-place --overlay "$work/overlay" --next "$next" --item "$item" "$dsc" "$OUT/$name"
	rm -rf "$work"
}
ITEM="The 3D switch is \"Ativar 3D\" in Brazilian Portuguese (ORDER 586): the label of \"Enable 3D\" was \"Ativar o 3D\", and one idea keeps one name in every program and every language."
one dragon "$POOL/d/dragon/dragon_26.04.0-1+stereo3d12+lc1.dsc" 4:26.04.0-1+stereo3d13 dragon-0015-The-3D-switch-is-Ativar-3D-in-Brazilian-Portuguese.patch 0015-The-3D-switch-is-Ativar-3D-in-Brazilian-Portuguese.patch "$ITEM Dragon Player writes it in its 3D Video settings page."
one haruna "$POOL/h/haruna/haruna_1.8.1-1+stereo3d5+lc1.dsc" 1.8.1-1+stereo3d6 haruna-0008-The-3D-switch-is-Ativar-3D-in-Brazilian-Portuguese.patch 0008-The-3D-switch-is-Ativar-3D-in-Brazilian-Portuguese.patch "$ITEM Haruna writes it in its 3D Video settings page."
