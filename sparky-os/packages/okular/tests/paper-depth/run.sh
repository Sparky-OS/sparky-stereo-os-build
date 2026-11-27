#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# run.sh IMAGE RESULTS [ROLE] -- queue row 121's proof of paper depth: Okular's page view and Qt's print preview on Stereo
# KWin's virtual output 1920x1080, one fresh container and KWin session per case.
#   IMAGE    an image with the packages under test installed by apt: Stereo KWin (kwin-wayland), libkscreen-bin, okular,
#            qt6-base-dev, g++, python3-gi, python3-numpy, python3-pil, dbus
#   RESULTS  an empty folder: bin/ (the print preview test program, compiled in IMAGE), one folder per case, verdicts.txt
#   ROLE     staged (the default: the desk one step down, the paper at the window's plane) or published (no step anywhere)
# BASELINE=FOLDER: a published run's RESULTS; the 2D cases must then match it pixel for pixel.
# KWin needs a render node (without one its virtual backend composites without OpenGL and ScreenShot2 cancels every capture):
# the NVIDIA card through CDI, its render node as the first one in the container (GPU=nvidia, the default; RENDER_NODE, by
# default /dev/dri/renderD129, and RENDER_GID, by default 125, name the host's); GPU=none gives no device. The programs
# draw with Mesa's software renderer.
# --cpus 4, --network none, --ulimit core=1, uid 1000; SYS_NICE, which kwin_wayland's file capability needs to start. PREFIX names the containers (default paper-depth); CIDS=FILE
# appends each container's ID to FILE.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=$1 RESULTS=$(mkdir -p "$2" && cd "$2" && pwd -P) ROLE=${3:-staged}
[ -z "$(ls -A "$RESULTS")" ] || { echo "$RESULTS is not empty" >&2; exit 2; }
PREFIX=${PREFIX:-paper-depth}
M2=${M2:-0}
CASES=${CASES:-okular-3d okular-scale12 okular-limit0 okular-scrolled okular-presentation okular-background okular-2d
	preview-3d preview-scale12 preview-limit0 preview-scrolled preview-background preview-2d}
echo "load at start $(date -u +%FT%TZ): $(cut -d' ' -f1-3 /proc/loadavg)" | tee "$RESULTS/load.txt"
end_load() {
    echo "load at end $(date -u +%FT%TZ): $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$RESULTS/load.txt"
}
trap end_load EXIT
docker image inspect "$IMAGE" --format '{{.Id}}' > "$RESULTS/image.txt"
gpu=()
[ "${GPU:-nvidia}" = nvidia ] && gpu=(--device nvidia.com/gpu=0 --device "${RENDER_NODE:-/dev/dri/renderD129}:/dev/dri/renderD128"
	--group-add "${RENDER_GID:-125}")
run() { # NAME [ENV...] -- COMMAND...
	local name=$PREFIX-$1; shift
	local env=()
	while [ "$1" != -- ]; do env+=(-e "$1"); shift; done; shift
	local cid=$RESULTS/.cid-$name
	docker run --rm --init --cidfile "$cid" --name "$name" --pull=never --ulimit core=1 --cpus 4 --network none \
		--user 1000:1000 --cap-add SYS_NICE --shm-size 512m "${gpu[@]}" "${env[@]}" \
		--mount "type=bind,src=$HERE,dst=/tests,readonly" --mount "type=bind,src=$RESULTS,dst=/out" \
		"$IMAGE" "$@" || echo "container $name rc=$?" >> "$RESULTS/containers.txt"
	if [ -n "${CIDS:-}" ] && [ -s "$cid" ]; then { cat "$cid"; echo; } >> "$CIDS"; fi
	rm -f "$cid"
}
run build -- bash -c 'mkdir -p /out/bin && g++ -O1 -fPIC -std=c++17 -o /out/bin/preview /tests/preview.cpp \
	$(pkg-config --cflags --libs Qt6Widgets Qt6PrintSupport) > /out/bin/build.log 2>&1; echo "build rc=$?" >> /out/bin/build.log;
	dpkg-query -W kwin-wayland okular libqt6widgets6 libqt6printsupport6 libqt6waylandclient6 > /out/bin/versions.txt'
if [ "$M2" = 1 ]; then
    run build-input -- bash -ec '
        tmp=$(mktemp -d)
        trap "rm -rf \"$tmp\"" EXIT
        xml=/usr/share/plasma-wayland-protocols/fake-input.xml
        wayland-scanner client-header "$xml" "$tmp/fake-input-client.h"
        wayland-scanner private-code "$xml" "$tmp/fake-input.c"
        cc -O2 -I"$tmp" /tests/input.c "$tmp/fake-input.c" -lwayland-client -lm -o /out/bin/input
        dpkg-query -W plasma-wayland-protocols calligrawords >> /out/bin/versions.txt'
    test -x "$RESULTS/bin/input"
    run build-words-style -- bash -ec '
        tmp=$(mktemp -d)
        trap "rm -rf \"$tmp\"" EXIT
        mkdir -p /out/bin/styles
        /usr/lib/qt6/libexec/moc $(pkg-config --cflags Qt6Widgets) /tests/words-desk-style.cpp -o "$tmp/words-desk-style.moc"
        g++ -O1 -fPIC -shared -I"$tmp" -o /out/bin/styles/libpaperdepth.so /tests/words-desk-style.cpp \
            $(pkg-config --cflags --libs Qt6Widgets)'
    test -s "$RESULTS/bin/styles/libpaperdepth.so"
fi
grep -q 'build rc=0' "$RESULTS/bin/build.log" || { cat "$RESULTS/bin/build.log"; exit 1; }
for case in $CASES; do
	element=1
	case $case in *-scale12) element=12 ;; *-limit0) element=0 ;; *-display|words-*) element=6 ;; probe-override) element=3 ;; esac
	run "$case" "ELEMENT=$element" "M2=$M2" "KCM_FIELD_XY=${KCM_FIELD_XY:-655 409}" "KCM_APPLY_XY=${KCM_APPLY_XY:-1035 924}" -- timeout 180 bash /tests/case.sh "$case"
	test -s "$RESULTS/$case/shot.png"
	run "measure-$case" -- bash -c 'case "$1" in
        probe-*) python3 -I /tests/measure-probe.py "/out/$1/shot.png" ;;
        *) python3 -I /tests/measure.py "/out/$1" "${1%%-*}" ;;
    esac > "/out/$1/measure.json" 2> "/out/$1/measure.err"
    if [ "${1##*-}" != 2d ]; then
        python3 -I /tests/mark_pns.py "/out/$1/shot.png" "/out/$1/shot.pns" > "/out/$1/pns.txt"
        if [ "$1" = okular-kcm ]; then
            for picture in kcm kcm-edited; do
                python3 -I /tests/mark_pns.py "/out/$1/$picture.png" "/out/$1/$picture.pns" >> "/out/$1/pns.txt"
            done
        fi
    fi' -- "$case"
	if [ -n "${BASELINE:-}" ] && [ "${case##*-}" = 2d ]; then
		# a 2D screen: the same pixels as the baseline's run of the same case
		base=$(cd "$BASELINE" && pwd -P)
		docker run --rm --name "$PREFIX-compare-$case" --pull=never --ulimit core=1 --cpus 1 --network none --user 1000:1000 \
			--mount "type=bind,src=$HERE,dst=/tests,readonly" --mount "type=bind,src=$RESULTS,dst=/out" \
			--mount "type=bind,src=$base,dst=/baseline,readonly" "$IMAGE" \
			python3 -I /tests/compare.py "/baseline/$case/shot.png" "/out/$case/shot.png" > "$RESULTS/$case/baseline.json"
	fi
done
if [ "$ROLE" != capture ]; then
    python3 -I "$HERE/verdicts.py" "$RESULTS" "$ROLE" ${BASELINE:+--baseline "$BASELINE"} | tee "$RESULTS/verdicts.txt"
fi
