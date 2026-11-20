#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 551c: builds the program's own "Enable 3D" of the album programs as packages, each through Lean
# Code with the link and start gate (../depth-source/build.sh), and collects them in a flat repository for the next one:
#   1. stereo-layer 1.19.2-1+lc1 from the fork clone (Stereo::Enable3DAction, Enable3DAction in QML)
#   2. gwenview 4:26.04.0-1+stereo3d11+lc1 from the published +10
#   3. koko 26.04.0-1+stereo3d3+lc1 and kphotoalbum 6.2.0-1+stereo3d3+lc1 from ORDER 551b's staged +2
#   4. digikam 4:9.1.0-1+stereo3d5+lc1 from ORDER 551b's staged +4; the large one, last
# The round follows two staged rounds: ORDER 551b (stereo-layer 1.19.0 and the three album programs, all rebuilt here) and
# ORDER 576 (stereo-layer 1.18.1, rebuilt here as 1.19.2, and dolphin +8, which this round's repository starts with,
# copied, so the installed proofs have it). The previous build the link gate compares with is the published one for every
# source (edition-packaging lessons, "A round that follows a staged round").
# Usage: round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR STAGE_551B STAGE_576 [STEP...]
#   WORK: the round's folder; a step that left its .done file is not run again
#   PUBLISHED_TREE: the signed published tree (read only); ARCHIVE_DIR: the link gate's folder (sources.json, keyrings)
#   STAGE_551B, STAGE_576: the two stage folders (read only; copied, never linked)
#   STEP: layer gwenview koko kphotoalbum digikam (all, in that order, when none is named)
# Environment: BUILD_NAME_PREFIX (container names, default ap-551c-build), THREADS (default 4), BUILD_WORK (a folder,
#   on a disk with room, where each source's build folder is made instead of WORK; the packages are still collected in WORK)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEPTH=$HERE/../depth-source
W=$(mkdir -p "$1" && cd "$1" && pwd) FORK=$(cd "$2" && pwd) REV=$3 TREE=$(cd "$4" && pwd) ARCHIVE=$(cd "$5" && pwd)
STAGE_551B=$(cd "$6" && pwd) STAGE_576=$(cd "$7" && pwd)
shift 7
STEPS=${*:-layer gwenview koko kphotoalbum digikam}
BW=$(mkdir -p "${BUILD_WORK:-$W}" && cd "${BUILD_WORK:-$W}" && pwd)
# A caller's own date for the whole round; without one each source takes the date of its own recipe (below)
ROUND_EPOCH=${SOURCE_DATE_EPOCH:-}
export BUILD_NAME_PREFIX=${BUILD_NAME_PREFIX:-ap-551c-build} THREADS=${THREADS:-4}
IMAGE=sparky-lc-migration:20261020
# the sources of this round and of the staged rounds it follows: their published binaries leave the candidate's siblings
ROUND='stereo-layer dolphin gwenview koko kphotoalbum digikam'
mkdir -p "$W/new"
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
open(os.path.join(new, 'Release'), 'w').write('Origin: Sparky Stereo OS\nLabel: ORDER 551c round\nArchitectures: amd64 all\n'
    f'Date: {email.utils.formatdate(usegmt=True)}\nSHA256:\n {hashlib.sha256(packages).hexdigest()} {len(packages)} Packages\n')
PY
}
if [ ! -f "$W/seed.done" ]; then
	# dolphin +8 of ORDER 576; ORDER 551b's four sources and both stereo-layer builds are rebuilt by this round
	cp --no-preserve=links "$STAGE_576"/dolphin/*.deb "$W/new/"
	index
	touch "$W/seed.done"
fi
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
build() { # build SOURCE SOURCE_DIR [PROFILES]
	local name=${1:?}
	index
	rm -rf "${BW:?}/${name}-work"
	ROUND_SOURCES=$ROUND SPARKY_BUILD_PROFILES=${3:-} "$DEPTH/build.sh" "$name" "$BW/$name-work" "$2" "$(previous "$name")" "$TREE" "$ARCHIVE" "$W/new" "$W/siblings.txt" \
		|| { echo "== $name: the build failed; the end of its log:"; tail -40 "$BW/$name-work/build.log"; exit 1; }
	grep -E 'link check passed|verified [0-9]+ packages|lc1 link note' "$BW/$name-work/build.log" | tail -8
	collect "$BW/$name-work"
}
in_container() { # in_container NAME ARGS...: a recipe script inside the migration container, no network
	local name=$1; shift
	docker run --rm --name "$name" --ulimit core=1 --cpus "$THREADS" --platform linux/amd64 --network none -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
		--mount type=bind,src="$TREE",dst=/repo,readonly --mount type=bind,src="$STAGE_551B",dst=/stage551b,readonly \
		--mount type=bind,src="$HERE/../..",dst=/toolkit,readonly --mount type=bind,src="$W",dst=/work \
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
		build stereo-layer "$W/stereo-layer-src" nocheck
		;;
	gwenview|koko|kphotoalbum|digikam)
		rm -rf "${W:?}/${step:?}-src"; mkdir -p "$W/$step-src"
		export SOURCE_DATE_EPOCH=$(python3 "$HERE/../../repo/reproducible.py" epoch "$HERE")
		if [ "$step" = gwenview ]; then
			dsc=/repo/$(cd "$TREE" && ls pool/main/g/gwenview/gwenview_*+lc1.dsc) orig=/repo/pool/main/g/gwenview
		else
			dsc=/stage551b/$step/$(cd "$STAGE_551B/$step" && ls "$step"_*+lc1.dsc) orig=/stage551b/$step
		fi
		# every command of the step must succeed: a source that was not made stops the round here, not in the build
		in_container "${BUILD_NAME_PREFIX}-source-$step" bash -c "set -e; export TMPDIR=/work/tmp-$step; mkdir -p /work/tmp-$step; bash /toolkit/packages/album-programs-551c/next-source.sh $step $dsc /work/$step-src; rmdir /work/tmp-$step 2>/dev/null || true; cp $orig/${step}_*.orig.tar.* /work/$step-src/; ls /work/$step-src/*+lc1.dsc" | tail -6
		build "$step" "$W/$step-src"
		;;
	*) echo "unknown step $step" >&2; exit 2 ;;
	esac
	touch "$W/$step.done"
done
(cd "$W/new" && sha256sum ./*.deb > SHA256SUMS && wc -l SHA256SUMS)
