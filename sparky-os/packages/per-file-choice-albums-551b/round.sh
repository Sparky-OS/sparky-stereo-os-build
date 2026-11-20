#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 551b: builds the per-file 3D choice of the album programs as packages, each through Lean Code
# with the link and start gate (../depth-source/build.sh), and collects them in a flat repository for the next one:
#   1. stereo-layer 1.19.0-1+lc1 from the fork clone (the QML form of the per-file menu), against the KImageFormats
#      plugin +stereo3d7 that ORDER 551 staged (SPARKY_BUILD_PROFILES=nocheck, as there)
#   2. koko 26.04.0-1+stereo3d2+lc1 and kphotoalbum 6.2.0-1+stereo3d2+lc1 (next-source.sh), against libstereo-layer-dev 1.19.0
#   3. digikam 4:9.1.0-1+stereo3d4+lc1 (next-source.sh), the same; the large one, last
# The round's repository starts with ORDER 551's staged packages except its stereo-layer 1.18.0, which 1.19.0 replaces:
# the plugin the layer depends on, and the programs of that round, are what the edition holds when these are published.
# Usage: round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR STAGE_551 [STEP...]
#   WORK: the round's folder; a step that left its .done file is not run again
#   PUBLISHED_TREE: the signed published tree (read only); ARCHIVE_DIR: the link gate's folder (sources.json, keyrings)
#   STAGE_551: ORDER 551's stage folder (read only; copied, never linked)
#   STEP: layer koko kphotoalbum digikam (all, in that order, when none is named)
# Environment: BUILD_NAME_PREFIX (container names, default pf-551b-build), THREADS (default 4)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEPTH=$HERE/../depth-source
W=$(mkdir -p "$1" && cd "$1" && pwd) FORK=$(cd "$2" && pwd) REV=$3 TREE=$(cd "$4" && pwd) ARCHIVE=$(cd "$5" && pwd) STAGE=$(cd "$6" && pwd)
shift 6
STEPS=${*:-layer koko kphotoalbum digikam}
# A caller's own date for the whole round; without one each source takes the date of its own recipe (below)
ROUND_EPOCH=${SOURCE_DATE_EPOCH:-}
export BUILD_NAME_PREFIX=${BUILD_NAME_PREFIX:-pf-551b-build} THREADS=${THREADS:-4}
IMAGE=sparky-lc-migration:20261020
# the sources of ORDER 551's round: their published binaries leave the candidate's siblings, their staged ones are in /new
ROUND_551='stereo-layer kf6-kimageformats kio-extras dolphin ffmpegthumbs gwenview'
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
open(os.path.join(new, 'Release'), 'w').write('Origin: Sparky Stereo OS\nLabel: ORDER 551b round\nArchitectures: amd64 all\n'
    f'Date: {email.utils.formatdate(usegmt=True)}\nSHA256:\n {hashlib.sha256(packages).hexdigest()} {len(packages)} Packages\n')
PY
}
if [ ! -f "$W/seed.done" ]; then
	for src in kf6-kimageformats kio-extras dolphin ffmpegthumbs gwenview; do cp --no-preserve=links "$STAGE/$src"/*.deb "$W/new/"; done
	index
	touch "$W/seed.done"
fi
collect() { # collect WORK_DIR: the debs of a finished build into the round's repository (copied, never linked)
	cp --no-preserve=links "$1"/lc/*.deb "$W/new/"
	index
}
previous() { # previous SOURCE: the published +lc1 debs of a source, for the link gate
	# The published build, for stereo-layer too (1.17.1): the gate qualifies the previous build against the previous
	# edition's snapshot, which is the published tree, and ORDER 551's staged 1.18.0 beside the published 1.17.1 there is
	# "conflicting supplied package: libstereo-av1; provide one authoritative edition snapshot".
	local dir=$W/$1-prev
	mkdir -p "$dir"
	cp "$TREE"/pool/main/"${1:0:1}"/"$1"/*+lc1_amd64.deb "$TREE"/pool/main/"${1:0:1}"/"$1"/*+lc1_all.deb "$dir/" 2>/dev/null || true
	echo "$dir"
}
build() { # build SOURCE SOURCE_DIR ROUND_SOURCES [PROFILES]
	local name=${1:?}
	index
	rm -rf "${W:?}/${name}-work"
	ROUND_SOURCES=$3 SPARKY_BUILD_PROFILES=${4:-} "$DEPTH/build.sh" "$name" "$W/$name-work" "$2" "$(previous "$name")" "$TREE" "$ARCHIVE" "$W/new" "$W/siblings.txt" \
		|| { echo "== $name: the build failed; the end of its log:"; tail -40 "$W/$name-work/build.log"; exit 1; }
	grep -E 'link check passed|verified [0-9]+ packages|lc1 link note' "$W/$name-work/build.log" | tail -8
	collect "$W/$name-work"
}
in_container() { # in_container NAME SCRIPT ARGS...: a recipe script inside the migration container, no network
	local name=$1; shift
	docker run --rm --name "$name" --ulimit core=1 --cpus "$THREADS" --platform linux/amd64 --network none -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
		--mount type=bind,src="$TREE",dst=/repo,readonly --mount type=bind,src="$HERE/../..",dst=/toolkit,readonly --mount type=bind,src="$W",dst=/work \
		--entrypoint bash "$IMAGE" -c 'set -e; "$@"; chown -R 1000:1000 /work' -- "$@"
}
for step in $STEPS; do
	[ ! -f "$W/$step.done" ] || { echo "== $step: done before"; continue; }
	echo "== $step"
	# The date of a source is its own recipe's: a date exported for one step must not reach the next (ORDER 551)
	if [ -n "$ROUND_EPOCH" ]; then export SOURCE_DATE_EPOCH=$ROUND_EPOCH; else unset SOURCE_DATE_EPOCH; fi
	case $step in
	layer)
		rm -rf "${W:?}/stereo-layer-src"; mkdir -p "$W/stereo-layer-src"
		SOURCE_NAME=${BUILD_NAME_PREFIX}-source-stereo-layer "$DEPTH/stereo-layer-source.sh" "$FORK" "$REV" "$W/stereo-layer-src" | tail -3
		build stereo-layer "$W/stereo-layer-src" "$ROUND_551" nocheck
		;;
	koko|kphotoalbum|digikam)
		rm -rf "${W:?}/${step:?}-src"; mkdir -p "$W/$step-src"
		export SOURCE_DATE_EPOCH=$(python3 "$HERE/../../repo/reproducible.py" epoch "$HERE")
		dsc=$(cd "$TREE" && ls pool/main/"${step:0:1}/$step/$step"_*+lc1.dsc)
		# every command of the step must succeed: a source that was not made stops the round here, not in the build
		in_container "${BUILD_NAME_PREFIX}-source-$step" bash -c "set -e; export TMPDIR=/work/tmp-$step; mkdir -p /work/tmp-$step; bash /toolkit/packages/per-file-choice-albums-551b/next-source.sh $step /repo/$dsc /work/$step-src; rmdir /work/tmp-$step 2>/dev/null || true; cp /repo/pool/main/${step:0:1}/$step/${step}_*.orig.tar.* /work/$step-src/; ls /work/$step-src/*+lc1.dsc" | tail -6
		build "$step" "$W/$step-src" "$ROUND_551 koko kphotoalbum digikam"
		;;
	*) echo "unknown step $step" >&2; exit 2 ;;
	esac
	touch "$W/$step.done"
done
(cd "$W/new" && sha256sum ./*.deb > SHA256SUMS && wc -l SHA256SUMS)
