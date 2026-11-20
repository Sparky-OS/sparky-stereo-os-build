#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 567: builds plasma-workspace 4:6.7.4-2+stereo3d8+lc1 and plasma-desktop 4:6.7.4-1+stereo3d4+lc1
# (panels on automatic hide while in tablet mode, and the switch for it), each from the source next-source.sh makes,
# through Lean Code with the link and start gate (../depth-source/build.sh). kwin +stereo3d55 has its own recipe
# (../kwin/build-55.sh); the two packages here need nothing of it to build.
# Usage: round.sh WORK PUBLISHED_TREE ARCHIVE_DIR [STEP...]
#   WORK: the round's folder; a step that left its .done file is not run again
#   PUBLISHED_TREE: the signed published tree (read only); ARCHIVE_DIR: the link gate's folder (sources.json, keyrings)
#   STEP: plasma-workspace plasma-desktop (both, in that order, when none is named)
# Environment: BUILD_NAME_PREFIX (container names, default cd-567-build), THREADS (default 4)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEPTH=$HERE/../depth-source
W=$(mkdir -p "$1" && cd "$1" && pwd) TREE=$(cd "$2" && pwd) ARCHIVE=$(cd "$3" && pwd)
shift 3
STEPS=${*:-plasma-workspace plasma-desktop}
ROUND_EPOCH=${SOURCE_DATE_EPOCH:-}
export BUILD_NAME_PREFIX=${BUILD_NAME_PREFIX:-cd-567-build} THREADS=${THREADS:-4}
IMAGE=sparky-lc-migration:20261020
# the published edition's .deb files as the build container sees them: what the publisher supplies as the destination pool
[ -s "$W/siblings.txt" ] || (cd "$TREE" && find pool -name '*.deb' ! -name '*-lc-hr_*' ! -name '*-dbgsym_*' | LC_ALL=C sort | sed 's|^|/repo/|') > "$W/siblings.txt"
for step in $STEPS; do
	case $step in plasma-workspace|plasma-desktop) ;; *) echo "unknown step $step" >&2; exit 2 ;; esac
	[ ! -f "$W/$step.done" ] || { echo "== $step: done before"; continue; }
	echo "== $step"
	# the date of a source is its own recipe's; a caller's own date holds for the whole round
	if [ -n "$ROUND_EPOCH" ]; then export SOURCE_DATE_EPOCH=$ROUND_EPOCH; else export SOURCE_DATE_EPOCH=$(python3 "$HERE/../../repo/reproducible.py" epoch "$HERE"); fi
	rm -rf "$W/$step-src" "$W/$step-work" "$W/$step-prev"; mkdir -p "$W/$step-src" "$W/$step-prev"
	pool=pool/main/${step:0:1}/$step
	dsc=$(cd "$TREE" && ls "$pool/$step"_*+lc1.dsc)
	docker run --rm --name "${BUILD_NAME_PREFIX}-source-$step" --ulimit core=1 --cpus "$THREADS" --platform linux/amd64 --network none -e SOURCE_DATE_EPOCH \
		-v "$TREE":/repo:ro -v "$HERE/../..":/toolkit:ro -v "$W":/work --entrypoint bash "$IMAGE" -c '
			set -e; step=$1 dsc=$2 pool=$3
			export TMPDIR=/work/tmp-$step; mkdir -p "$TMPDIR"
			/toolkit/packages/convertible-defaults-567/next-source.sh "$step" "/repo/$dsc" "/work/$step-src"
			rm -rf "$TMPDIR"
			cp /repo/"$pool"/*.orig.tar.* "/work/$step-src/"
			chown -R 1000:1000 /work' -- "$step" "$dsc" "$pool" | tail -4
	cp "$TREE/$pool"/*+lc1_amd64.deb "$W/$step-prev/" 2>/dev/null || true
	cp "$TREE/$pool"/*+lc1_all.deb "$W/$step-prev/" 2>/dev/null || true
	"$DEPTH/build.sh" "$step" "$W/$step-work" "$W/$step-src" "$W/$step-prev" "$TREE" "$ARCHIVE" "" "$W/siblings.txt" \
		|| { echo "== $step: the build failed; the end of its log:"; tail -40 "$W/$step-work/build.log"; exit 1; }
	grep -E 'link check passed|verified [0-9]+ packages' "$W/$step-work/build.log" | tail -4
	touch "$W/$step.done"
done
