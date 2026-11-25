#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Make the Vibe successor of the complete staged Kdenlive source.
set -euo pipefail
recipe=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(cd "$recipe/../.." && pwd)
predecessor=$(realpath "${1:?predecessor .dsc}")
output=$(realpath -m "${2:?new output directory}")
image=${3:?build image}
epoch=$(python3 "$toolkit/repo/reproducible.py" epoch "$recipe")
mkdir "$output"
overlay=$(mktemp -d)
trap 'rm -r "$overlay"' EXIT
mkdir "$overlay/patches"
version=$(sed -n 's/^Version: //p' "$predecessor")
case "$version" in
  26.08.1-1+stereo3d14+lc1)
    next=26.08.1-1+stereo3d15
    patch=0030-align-Vibe-words-and-bound-speech-audio-export.patch
    catalogue=kdenlive-order74-timing.po.patch
    cp "$recipe/patches/$patch" "$toolkit/translations/$catalogue" "$overlay/patches/"
    patches=("$patch" "$catalogue")
    notes=(--item "Align Vibe cues to its timed words and the exported audio, and support Vibe in the Speech Editor."
           --item "Run the shared speech WAV export out of process with a bounded wait for written audio.")
    ;;
  26.08.1-1+stereo3d15+lc1)
    next=26.08.1-1+stereo3d16
    patches=(0031-watch-renderer-progress-for-speech-audio.patch 0032-ignore-isolated-impulses-when-aligning-speech.patch)
    for patch in "${patches[@]}"; do cp "$recipe/patches/$patch" "$overlay/patches/"; done
    notes=(--item "Track renderer progress during speech audio export and record its state at a timeout."
           --item "Ignore isolated clicks when aligning the spoken edges of a cue.")
    ;;
  *) printf 'Unsupported Kdenlive predecessor %s\n' "$version" >&2; exit 2 ;;
esac
tar -xJOf "${predecessor%.dsc}.debian.tar.xz" debian/patches/series > "$overlay/patches/series"
printf '%s\n' "${patches[@]}" >> "$overlay/patches/series"
name="${SPARKY_CONTAINER_PREFIX:-kdenlive-vibe}-sources"
container_id=$(docker create --pull=never --ulimit core=1 --network none --cpus "${SPARKY_SOURCE_CPUS:-4}" --platform linux/amd64 \
  --name "$name" --user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$epoch" \
  -e DEBFULLNAME="Daniel Ramos (Capitain Jack)" -e DEBEMAIL=Capitain_Jack@yahoo.com \
  -v "$(dirname "$predecessor")":/predecessor:ro -v "$overlay":/overlay:ro -v "$toolkit":/toolkit:ro -v "$output":/out \
  "$image" python3 /toolkit/repo/lc-successor.py --in-place --overlay /overlay --reapply-patches \
  --work /tmp --source-date-epoch "$epoch" --next "$next" "${notes[@]}" \
  "/predecessor/$(basename "$predecessor")" /out)
trap 'docker rm "$name" >/dev/null; rm -r "$overlay"' EXIT
if [[ -n ${SPARKY_CONTAINER_IDS:-} ]]; then printf '%s\n' "$container_id" >> "$SPARKY_CONTAINER_IDS"; fi
docker start -a "$name"
test "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = 0
cp "$(dirname "$predecessor")"/kdenlive_26.08.1.orig.tar.xz* "$output/"
