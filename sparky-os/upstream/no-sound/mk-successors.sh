#!/bin/bash
# Sparky Stereo OS: the next +lc1 sources of Bino, Haruna, Dragon Player and Plank Player, each the published source with one
# patch more (ORDER 579: a film with a picture and no audio track says so), made with repo/lc-successor.py --in-place --overlay.
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Usage: mk-successors.sh OUT PUBLISHED_POOL LAYER_VERSION
#   OUT: receives one folder per source (the new .dsc and Debian tarball); PUBLISHED_POOL: the repository's pool/main folder;
#   LAYER_VERSION: the stereo layer's version the players need (1.21.0-1+lc1).
set -euo pipefail
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
POOL=${2:?} LAYER=${3:?}
EPOCH=$(python3 "$TREE/sparky-os/repo/reproducible.py" epoch "$HERE")
export SOURCE_DATE_EPOCH=$EPOCH
one() { # NAME DSC NEXT PATCHFILE PATCHNAME ITEM [--depends OLD NEW]...
	local name=$1 dsc=$2 next=$3 patch=$4 pname=$5 item=$6; shift 6
	local work; work=$(mktemp -d "$OUT/.work.XXXXXX")
	dpkg-source -x --no-check "$dsc" "$work/old" >/dev/null
	mkdir -p "$work/overlay/patches"
	cp "$HERE/patches/$patch" "$work/overlay/patches/$pname"
	{ cat "$work/old/debian/patches/series"; echo "$pname"; } > "$work/overlay/patches/series"
	mkdir -p "$OUT/$name"
	python3 "$TREE/sparky-os/repo/lc-successor.py" --in-place --overlay "$work/overlay" --next "$next" --item "$item" "$@" "$dsc" "$OUT/$name"
	rm -rf "$work"
}
ITEM="A film with a picture and no audio track says so (ORDER 579): the sentence \"This film has no sound.\" in the ten languages, in the player's own way of telling, beside its volume control; the volume control stays usable."
one bino "$POOL/b/bino/bino_2.8-1+stereo3d9+lc1.dsc" 2.8-1+stereo3d10 bino-0007-Say-when-a-film-has-no-sound.patch 0007-Say-when-a-film-has-no-sound.patch "$ITEM Bino takes the sentence and the rule from the stereo layer $LAYER." \
	--depends "libstereo-layer-dev (>= 1.12.0-4+lc1)" "libstereo-layer-dev (>= $LAYER)" --depends "libstereo-layer1 (>= 1.12.0-4+lc1)" "libstereo-layer1 (>= $LAYER)"
one haruna "$POOL/h/haruna/haruna_1.8.1-1+stereo3d4+lc1.dsc" 1.8.1-1+stereo3d5 haruna-0007-Say-when-a-film-has-no-sound.patch 0007-Say-when-a-film-has-no-sound.patch "$ITEM Haruna says it in its OSD and in the tooltips of the volume slider and the mute button, from mpv's track list."
one dragon "$POOL/d/dragon/dragon_26.04.0-1+stereo3d11+lc1.dsc" 4:26.04.0-1+stereo3d12 dragon-0014-Say-when-a-film-has-no-sound.patch 0014-Say-when-a-film-has-no-sound.patch "$ITEM Dragon Player says it in a message in the window and in the tooltip of the volume button, with the sentence and the rule of the stereo layer $LAYER." \
	--depends "libstereo-layer1 (>= 1.17.1)" "libstereo-layer1 (>= $LAYER)"
one plank-player "$POOL/p/plank-player/plank-player_5.27.80+git20261005.f87e775-1+stereo3d4+lc1.dsc" 5.27.80+git20261005.f87e775-1+stereo3d5 plank-player-0007-Say-when-a-film-has-no-sound.patch 0007-Say-when-a-film-has-no-sound.patch "$ITEM Plank Player says it in a banner and in its OSD."
