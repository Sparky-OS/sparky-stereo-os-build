#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Make MLT 7.40.0-1+stereo3d13+lc1 from the staged +stereo3d12 source: upstream's repair of the avformat
# consumer's start (MLT pull request 1366, issue 1333) as the four commits it merged, each with its author.
# Without it a consumer whose thread reached its loop before the starter had set "running" stopped at once
# and looked running for ever: Kdenlive's speech audio export waited on it (ORDER 74).
# Usage: make-mlt-source.sh PREDECESSOR.dsc NEW_OUTPUT_DIR IMAGE
set -euo pipefail
recipe=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(cd "$recipe/../.." && pwd)
predecessor=$(realpath "${1:?the staged mlt_7.40.0-1+stereo3d12+lc1.dsc}")
output=$(realpath -m "${2:?new output directory}")
image=${3:?build image}
# ORDER 61e's staged source, by its sum: nothing else is a predecessor of this recipe.
printf '%s  %s\n' 2ca6f1c8dd602e7da8a67bc05e5ad2463365c02d4a34a600be10193c53effb62 "$predecessor" | sha256sum --check --quiet
epoch=$(python3 "$toolkit/repo/reproducible.py" epoch "$recipe")
mkdir "$output"
overlay=$(mktemp -d)
trap 'rm -r "$overlay"' EXIT
mkdir "$overlay/patches"
cp "$recipe"/patches-mlt/*.patch "$overlay/patches/"
tar -xJOf "${predecessor%.dsc}.debian.tar.xz" debian/patches/series > "$overlay/patches/series"
(cd "$recipe/patches-mlt" && printf '%s\n' *.patch) >> "$overlay/patches/series"
name="${SPARKY_CONTAINER_PREFIX:-kdenlive-vibe}-mlt-sources"
container_id=$(docker create --pull=never --ulimit core=1 --network none --cpus "${SPARKY_SOURCE_CPUS:-4}" --platform linux/amd64 \
  --name "$name" --user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$epoch" \
  -e DEBFULLNAME="Daniel Ramos (Capitain Jack)" -e DEBEMAIL=Capitain_Jack@yahoo.com \
  -v "$(dirname "$predecessor")":/predecessor:ro -v "$overlay":/overlay:ro -v "$toolkit":/toolkit:ro -v "$output":/out \
  "$image" python3 /toolkit/repo/lc-successor.py --in-place --overlay /overlay --reapply-patches \
  --work /tmp --source-date-epoch "$epoch" --next 7.40.0-1+stereo3d13 \
  --item "The avformat consumer is set running before its thread starts, and its start waits until the thread is ready or has failed: a consumer whose thread reached its loop first stopped at once and then looked running for ever, so a program waiting for it (Kdenlive's speech audio export, melt) never ended. Upstream's pull request 1366 for issue 1333, carried as its four commits by Erich Seifert, tydude001 and Brian Matherly (patches 0022 to 0025)." \
  --item "An event waiter set up before the event no longer blocks the event's delivery, and an event fired before the wait is not lost (patch 0025, Brian Matherly)." \
  "/predecessor/$(basename "$predecessor")" /out)
trap 'docker rm "$name" >/dev/null; rm -r "$overlay"' EXIT
if [[ -n ${SPARKY_CONTAINER_IDS:-} ]]; then printf '%s\n' "$container_id" >> "$SPARKY_CONTAINER_IDS"; fi
docker start -a "$name"
test "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = 0
cp "$(dirname "$predecessor")"/mlt_7.40.0.orig.tar.gz "$output/"
