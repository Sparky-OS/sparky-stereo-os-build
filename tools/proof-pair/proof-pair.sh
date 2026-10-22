#!/bin/bash
# proof-pair: one side-by-side capture (left eye first) -> NAME.mpo and NAME-anaglyph.jpg,
# the edition's proof standard: an MPO and a red/cyan anaglyph of every published proof.
# Usage: proof-pair.sh side-by-side.png OUTDIR/NAME
set -euo pipefail
in=$1; out=$2; here=$(cd "$(dirname "$0")" && pwd)
QT_QPA_PLATFORM=offscreen "$here/sbs2mpo" "$in" "$out.mpo"
# Dubois red/cyan, the least ghosting of the anaglyph matrices (FFmpeg stereo3d, arcd)
ffmpeg -loglevel error -y -i "$in" -vf stereo3d=sbsl:arcd -q:v 3 "$out-anaglyph.jpg"
echo "$out.mpo $out-anaglyph.jpg"
