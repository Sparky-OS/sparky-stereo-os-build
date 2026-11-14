#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 551: builds the per-file 3D choice as packages, in the order their dependencies need, each through
# Lean Code with the link and start gate (../depth-source/build.sh), and collects them in a flat repository for the next one:
#   0. a bootstrap of libstereo-policy1 and libstereo-policy-dev: a plain build of the layer's source, used for step 1 only.
#      libstereo-layer1 depends on the KImageFormats plugin of step 1 (>= +stereo3d6), and that plugin is built against the
#      layer's policy library, so neither passes the link gate before the other exists; the policy library depends on
#      neither. The bootstrap debs leave the round's repository when step 1 is done and are never published.
#   1. kf6-kimageformats 6.30.0-1+stereo3d7+lc1 (../jps-descriptor, ORDER 526) against the bootstrap libstereo-policy-dev
#   2. stereo-layer 1.18.0-1+lc1 from the fork clone, with the plugin of step 1 in the round's repository
#      (SPARKY_BUILD_PROFILES=nocheck: the package build runs no tests, and its test dependencies stay out of the build)
#   3. kio-extras 4:26.04.0-1+stereo3d5+lc1 as ORDER 504 staged it (KIO_EXTRAS_DIR: its .deb files, copied, not rebuilt)
#   4. dolphin 4:26.08.0-1+stereo3d7+lc1, ffmpegthumbs 4:26.04.0-1+stereo3d5+lc1, gwenview 4:26.04.0-1+stereo3d10+lc1
#      (next-source.sh), each built against libstereo-layer-dev 1.18.0
# Usage: round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR KIO_EXTRAS_DIR [STEP...]
#   WORK: the round's folder; a step that left its .done file is not run again
#   PUBLISHED_TREE: the signed published tree (read only); ARCHIVE_DIR: the link gate's folder (sources.json, keyrings)
#   STEP: bootstrap kimageformats layer kio-extras dolphin ffmpegthumbs gwenview (all, in that order, when none is named)
# Environment: BUILD_NAME_PREFIX (container names, default pf-551-build), THREADS (default 4)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEPTH=$HERE/../depth-source
W=$(mkdir -p "$1" && cd "$1" && pwd) FORK=$(cd "$2" && pwd) REV=$3 TREE=$(cd "$4" && pwd) ARCHIVE=$(cd "$5" && pwd) KIO=$(cd "$6" && pwd)
shift 6
STEPS=${*:-bootstrap kimageformats layer kio-extras dolphin ffmpegthumbs gwenview}
export BUILD_NAME_PREFIX=${BUILD_NAME_PREFIX:-pf-551-build} THREADS=${THREADS:-4}
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
open(os.path.join(new, 'Release'), 'w').write('Origin: Sparky Stereo OS\nLabel: ORDER 551 round\nArchitectures: amd64 all\n'
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
	ls "$W"/new/*.deb >/dev/null 2>&1 && new=$W/new
	rm -rf "$W/$1-work"
	ROUND_SOURCES=$3 SPARKY_BUILD_PROFILES=${4:-} "$DEPTH/build.sh" "$1" "$W/$1-work" "$2" "$(previous "$1")" "$TREE" "$ARCHIVE" "$new" "$W/siblings.txt" \
		|| { echo "== $1: the build failed; the end of its log:"; tail -40 "$W/$1-work/build.log"; exit 1; }
	grep -E 'link check passed|verified [0-9]+ packages' "$W/$1-work/build.log" | tail -4
	collect "$W/$1-work"
}
in_container() { # in_container NAME SCRIPT ARGS...: a recipe script inside the migration container, no network
	local name=$1; shift
	docker run --rm --name "$name" --ulimit core=0 --cpus "$THREADS" --platform linux/amd64 --network none -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
		-v "$TREE":/repo:ro -v "$HERE/../..":/toolkit:ro -v "$W":/work --entrypoint bash "$IMAGE" -c 'set -e; "$@"; chown -R 1000:1000 /work' -- "$@"
}
for step in $STEPS; do
	[ ! -f "$W/$step.done" ] || { echo "== $step: done before"; continue; }
	echo "== $step"
	case $step in
	bootstrap)
		rm -rf "$W/bootstrap"; mkdir -p "$W/bootstrap"
		docker run --rm -i --name "${BUILD_NAME_PREFIX}-bootstrap-policy" --ulimit core=0 --cpus "$THREADS" --platform linux/amd64 -e REV="$REV" -e THREADS="$THREADS" \
			-v "$FORK":/fork:ro -v "$TREE":/repo:ro -v "$W/bootstrap":/out \
			-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
			-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
			--entrypoint bash "$IMAGE" -c 'sh /run/https-only-apt.sh && bash -s' > "$W/bootstrap.log" 2>&1 <<'INNER' || { tail -30 "$W/bootstrap.log"; exit 1; }
set -euo pipefail
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="nocheck parallel=$THREADS" DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
git config --global safe.directory '*'
mkdir -p /b/source && git -C /fork archive "$REV" | tar -x -C /b/source
# this script arrives on standard input: every command that could read it is given /dev/null, or it eats the lines below
apt-get -y update </dev/null >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep -P nocheck /b/source </dev/null >/out/build-dep.log 2>&1
cd /b/source && dpkg-buildpackage -b -us -uc -Pnocheck -j"$THREADS" </dev/null >/out/build.log 2>&1
cp /b/libstereo-policy1_*_amd64.deb /b/libstereo-policy-dev_*_amd64.deb /out/
chown -R 1000:1000 /out
ls /out/*.deb
INNER
		tail -2 "$W/bootstrap.log"
		cp --no-preserve=links "$W"/bootstrap/*.deb "$W/new/"
		index
		;;
	layer)
		# the bootstrap policy library has done its work: the round's repository holds only what is built through the gate
		for deb in "$W"/bootstrap/*.deb; do [ ! -e "$deb" ] || rm -f "$W/new/$(basename "$deb")"; done
		index
		rm -rf "$W/stereo-layer-src"; mkdir -p "$W/stereo-layer-src"
		SOURCE_NAME=${BUILD_NAME_PREFIX}-source-stereo-layer "$DEPTH/stereo-layer-source.sh" "$FORK" "$REV" "$W/stereo-layer-src" | tail -3
		build stereo-layer "$W/stereo-layer-src" 'stereo-layer' nocheck
		;;
	kimageformats)
		rm -rf "$W/kf6-kimageformats-src"; mkdir -p "$W/kf6-kimageformats-src"
		export SOURCE_DATE_EPOCH=$(python3 "$HERE/../../repo/reproducible.py" epoch "$HERE/../jps-descriptor")
		docker run --rm --name "${BUILD_NAME_PREFIX}-source-kimageformats" --ulimit core=0 --cpus "$THREADS" --platform linux/amd64 --network none -e SOURCE_DATE_EPOCH \
			-v "$TREE/pool/main/k/kf6-kimageformats":/in:ro -v "$HERE/../..":/toolkit:ro -v "$W/kf6-kimageformats-src":/out \
			--entrypoint bash "$IMAGE" /toolkit/packages/per-file-choice-551/kimageformats-source.sh | tail -4
		build kf6-kimageformats "$W/kf6-kimageformats-src" 'stereo-layer kf6-kimageformats'
		;;
	kio-extras)
		ls "$KIO"/kio-extras_*+stereo3d5+lc1_amd64.deb "$KIO"/kio-extras-data_*+stereo3d5+lc1_all.deb >/dev/null
		cp --no-preserve=links "$KIO"/kio-extras_*+stereo3d5+lc1_amd64.deb "$KIO"/kio-extras-data_*+stereo3d5+lc1_all.deb "$W/new/"
		index
		;;
	dolphin|ffmpegthumbs|gwenview)
		rm -rf "$W/$step-src"; mkdir -p "$W/$step-src"
		export SOURCE_DATE_EPOCH=$(python3 "$HERE/../../repo/reproducible.py" epoch "$HERE")
		dsc=$(cd "$TREE" && ls pool/main/"${step:0:1}/$step/$step"_*+lc1.dsc)
		in_container "${BUILD_NAME_PREFIX}-source-$step" bash -c "TMPDIR=/work/tmp-$step; mkdir -p \$TMPDIR; export TMPDIR; /toolkit/packages/per-file-choice-551/next-source.sh $step /repo/$dsc /work/$step-src; rm -rf \$TMPDIR; cp /repo/pool/main/${step:0:1}/$step/${step}_*.orig.tar.* /work/$step-src/" | tail -6
		build "$step" "$W/$step-src" 'stereo-layer kf6-kimageformats kio-extras dolphin ffmpegthumbs gwenview'
		;;
	*) echo "unknown step $step" >&2; exit 2 ;;
	esac
	touch "$W/$step.done"
done
(cd "$W/new" && sha256sum ./*.deb > SHA256SUMS && wc -l SHA256SUMS)
