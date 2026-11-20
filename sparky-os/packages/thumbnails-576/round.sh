#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 576: builds the stereo layer and Dolphin whose 3D thumbnails are right at every scale, each
# through Lean Code with the link and start gate (../depth-source/build.sh), after ../per-file-choice-551/round.sh:
#   1. stereo-layer 1.18.1-1+lc1 from the fork clone (SPARKY_BUILD_PROFILES=nocheck: the package build runs no tests,
#      and its test dependencies stay out of the build)
#   2. dolphin 4:26.08.0-1+stereo3d8+lc1 (next-source.sh), built against libstereo-layer-dev 1.18.1 of step 1
# Usage: round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR [STEP...]
#   WORK: the round's folder; a step that left its .done file is not run again
#   PUBLISHED_TREE: the signed published tree (read only); ARCHIVE_DIR: the link gate's folder (sources.json, keyrings)
#   STEP: layer dolphin (both, in that order, when none is named)
# Environment: BUILD_NAME_PREFIX (container names, default dt-576-build), THREADS (default 4)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEPTH=$HERE/../depth-source
W=$(mkdir -p "$1" && cd "$1" && pwd) FORK=$(cd "$2" && pwd) REV=$3 TREE=$(cd "$4" && pwd) ARCHIVE=$(cd "$5" && pwd)
shift 5
STEPS=${*:-layer dolphin}
# A caller's own date for the whole round; without one each source takes the date of its own recipe (below)
ROUND_EPOCH=${SOURCE_DATE_EPOCH:-}
export BUILD_NAME_PREFIX=${BUILD_NAME_PREFIX:-dt-576-build} THREADS=${THREADS:-4}
IMAGE=sparky-lc-migration:20261020
mkdir -p "$W/new"
# the published edition's .deb files as the build container sees them: what the publisher supplies as the destination pool
[ -s "$W/siblings.txt" ] || (cd "$TREE" && find pool -name '*.deb' ! -name '*-lc-hr_*' ! -name '*-dbgsym_*' | LC_ALL=C sort | sed 's|^|/repo/|') > "$W/siblings.txt"

# The flat repository of the round, with the edition's Origin: the build container pins that origin at 1001, and a
# repository without it loses to the published version of the same package (../depth-source/README.md).
index() {
	python3 - "$W/new" <<'PY'
import hashlib, os, subprocess, sys, email.utils
new = sys.argv[1]
stanzas = []
for name in sorted(os.listdir(new)):
    if not name.endswith('.deb'):
        continue
    path = os.path.join(new, name)
    control = subprocess.run(['dpkg-deb', '-f', path], check=True, capture_output=True, text=True).stdout.rstrip('\n')
    data = open(path, 'rb').read()
    stanzas.append(f'{control}\nFilename: ./{name}\nSize: {len(data)}\nSHA256: {hashlib.sha256(data).hexdigest()}\n')
packages = '\n'.join(stanzas).encode()
open(os.path.join(new, 'Packages'), 'wb').write(packages)
open(os.path.join(new, 'Release'), 'w').write('Origin: Sparky Stereo OS\nLabel: ORDER 576 round\nArchitectures: amd64 all\n'
    f'Date: {email.utils.formatdate(usegmt=True)}\nSHA256:\n {hashlib.sha256(packages).hexdigest()} {len(packages)} Packages\n')
PY
}
collect() { # collect WORK_DIR: the debs of a finished build into the round's repository (copied, never linked)
	cp --no-preserve=links "$1"/lc/*.deb "$W/new/"
	index
}
previous() { # previous SOURCE: the published +lc1 debs of a source, for the link gate
	local dir=$W/$1-prev
	mkdir -p "$dir"
	cp "$TREE"/pool/main/"${1:0:1}"/"$1"/*+lc1_amd64.deb "$TREE"/pool/main/"${1:0:1}"/"$1"/*+lc1_all.deb "$dir/" 2>/dev/null || true
	echo "$dir"
}
build() { # build SOURCE SOURCE_DIR ROUND_SOURCES [PROFILES]
	local new=
	# the index follows what the folder holds now (a file taken out by hand between two runs is out of it)
	ls "$W"/new/*.deb >/dev/null 2>&1 && { index; new=$W/new; }
	rm -rf "$W/$1-work"
	ROUND_SOURCES=$3 SPARKY_BUILD_PROFILES=${4:-} "$DEPTH/build.sh" "$1" "$W/$1-work" "$2" "$(previous "$1")" "$TREE" "$ARCHIVE" "$new" "$W/siblings.txt" \
		|| { echo "== $1: the build failed; the end of its log:"; tail -40 "$W/$1-work/build.log"; exit 1; }
	grep -E 'link check passed|verified [0-9]+ packages' "$W/$1-work/build.log" | tail -4
	collect "$W/$1-work"
}
in_container() { # in_container NAME SCRIPT ARGS...: a recipe script inside the migration container, no network
	local name=$1; shift
	docker run --rm --name "$name" --ulimit core=1 --cpus "$THREADS" --platform linux/amd64 --network none -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
		-v "$TREE":/repo:ro -v "$HERE/../..":/toolkit:ro -v "$W":/work --entrypoint bash "$IMAGE" -c 'set -e; "$@"; chown -R 1000:1000 /work' -- "$@"
}
for step in $STEPS; do
	[ ! -f "$W/$step.done" ] || { echo "== $step: done before"; continue; }
	echo "== $step"
	# The date of a source is its own recipe's (repo/reproducible.py epoch gives the environment's date when there is
	# one): a date exported for one step must not reach the next, or a round built in one go dates every later source
	# by the first recipe's commit.
	if [ -n "$ROUND_EPOCH" ]; then export SOURCE_DATE_EPOCH=$ROUND_EPOCH; else unset SOURCE_DATE_EPOCH; fi
	case $step in
	layer)
		rm -rf "$W/stereo-layer-src"; mkdir -p "$W/stereo-layer-src"
		SOURCE_NAME=${BUILD_NAME_PREFIX}-source-stereo-layer "$DEPTH/stereo-layer-source.sh" "$FORK" "$REV" "$W/stereo-layer-src" | tail -3
		build stereo-layer "$W/stereo-layer-src" 'stereo-layer dolphin' nocheck
		;;
	dolphin)
		rm -rf "$W/$step-src"; mkdir -p "$W/$step-src"
		export SOURCE_DATE_EPOCH=$(python3 "$HERE/../../repo/reproducible.py" epoch "$HERE")
		dsc=$(cd "$TREE" && ls pool/main/"${step:0:1}/$step/$step"_*+lc1.dsc)
		in_container "${BUILD_NAME_PREFIX}-source-$step" bash -c "TMPDIR=/work/tmp-$step; mkdir -p \$TMPDIR; export TMPDIR; /toolkit/packages/thumbnails-576/next-source.sh /repo/$dsc /work/$step-src; rm -rf \$TMPDIR; cp /repo/pool/main/${step:0:1}/$step/${step}_*.orig.tar.* /work/$step-src/" | tail -6
		build "$step" "$W/$step-src" 'stereo-layer dolphin'
		;;
	*) echo "unknown step $step" >&2; exit 2 ;;
	esac
	touch "$W/$step.done"
done
(cd "$W/new" && sha256sum ./*.deb > SHA256SUMS && wc -l SHA256SUMS)
