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
cp "$recipe"/patches/*.patch "$toolkit/translations/kdenlive-order74.po.patch" "$overlay/patches/"
tar -xJOf "${predecessor%.dsc}.debian.tar.xz" debian/patches/series > "$overlay/patches/series"
printf '%s\n' 0028-speechdialog-release-xml-lock-before-processing-events.patch \
  0029-add-local-Vibe-subtitle-recognition.patch kdenlive-order74.po.patch >> "$overlay/patches/series"
name="${SPARKY_CONTAINER_PREFIX:-kdenlive-vibe}-sources"
container_id=$(docker create --pull=never --ulimit core=1 --network none --cpus 4 --platform linux/amd64 \
  --name "$name" --user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$epoch" \
  -e DEBFULLNAME="Daniel Ramos (Capitain Jack)" -e DEBEMAIL=Capitain_Jack@yahoo.com \
  -v "$(dirname "$predecessor")":/predecessor:ro -v "$overlay":/overlay:ro -v "$toolkit":/toolkit:ro -v "$output":/out \
  "$image" python3 /toolkit/repo/lc-successor.py --in-place --overlay /overlay --reapply-patches \
  --work /tmp --source-date-epoch "$epoch" --next 26.08.1-1+stereo3d14 \
  --item "Carry Erich Seifert's fix for autosaving during automatic subtitling (KDE Invent !1097)." \
  --item "Add optional local Vibe speech recognition for timeline subtitles and follow the installed Partners speech settings." \
  --depends 'libmlt7 (>= 7.40.0-1+stereo3d12+lc1)' 'libmlt7 (>= 7.40.0-1+stereo3d12+lc1), sparky-stereo-partners (>= 0.1.5+lc1)' \
  "/predecessor/$(basename "$predecessor")" /out)
trap 'docker rm "$name" >/dev/null; rm -r "$overlay"' EXIT
if [[ -n ${SPARKY_CONTAINER_IDS:-} ]]; then printf '%s\n' "$container_id" >> "$SPARKY_CONTAINER_IDS"; fi
docker start -a "$name"
test "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = 0
cp "$(dirname "$predecessor")"/kdenlive_26.08.1.orig.tar.xz* "$output/"
