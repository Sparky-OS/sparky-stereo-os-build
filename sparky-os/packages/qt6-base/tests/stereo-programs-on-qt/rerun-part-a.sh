#!/bin/bash
# rerun-part-a.sh [OUT] -- row 863 part A in one command: the published programs on the staged qt6-base +stereo3d24
# (with sparky-stereo-graphics 0.2.18) against the published set, one fresh Stereo KWin session per case, from this
# folder alone (build main's sparky-os/upstream for the programs' own measures, gl-shim.c and VLC's clip maker, or
# R863_UPSTREAM: a folder with the same layout holding those files, as the row 863 kit carries them).
#   A1 a1.sh     Kubrick, KAlgebra, Kalzium, Fraqtive: the 3D area a pair over its widget at the start, after resizes,
#                tab and dock changes and full screen; each program's own proof measure; lag-selftest.py (the wire-log
#                measure's known bad cases)
#   A2-A6 a2-a6.sh  VLC Stereo's video surface (Qt 5); Krita's stereo canvas layer and its known bad case; Qt's own
#                frame resized by its edge and its known bad case; the installer's slideshow in a window of its own;
#                Octave's 2D-screen row on Xvfb
# Images it starts from (kept): sc50i-rig:a863-pubg and sc50i-rig:a863-q24 (make-images.sh; REBUILD_IMAGES=1 makes them
# again, with the network for apt), and sc50i-rig:oct863-pkg-doc2 (the row 863 kit's Octave image, read only), from
# which a2-a6.sh makes sc50i-rig:a863-oct-x and :a863-oct-x24 (Debian's snapshot over https). The probes are built
# again (the Qt 5 one in a throwaway container with apt's network). Writes only under OUT (default a new folder in
# /var/tmp/qt-flush-863/parta). About 45 minutes; exit 0 only when every row is as expected.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
L=/K3D/partners/queue/science-stereo-ship-and-upstream-50; K=/var/lib/sparky-lanes/science-50i/kept-freecad
export DOCKER_HOST=unix://$L/docker.sock ROW863_CONTAINER_IDS=${ROW863_CONTAINER_IDS:-$L/.container-ids}
OUT=${1:-/var/tmp/qt-flush-863/parta/rerun-$(date -u +%Y%m%dT%H%M%SZ)}
[ -e "$OUT" ] && { echo "$OUT exists: give a new folder" >&2; exit 2; }
mkdir -p "$OUT/bin"
echo "load at start: $(cut -d' ' -f1-3 /proc/loadavg) ($(date -u +%TZ))"
need=0
for img in sc50i-rig:a863-pubg sc50i-rig:a863-q24 sc50i-rig:oct863-pkg-doc2 sc50i-rig:qt863-pub; do
	docker image inspect "$img" > /dev/null 2>&1 || { echo "image $img is missing"; need=1; }
done
if [ "${REBUILD_IMAGES:-0}" = 1 ] || [ $need = 1 ]; then
	bash "$HERE/make-images.sh" "$OUT/images" || { echo "the images could not be made"; exit 1; }
fi
cid=$OUT/bin/cid; rm -f "$cid"
docker run --rm --cidfile "$cid" --name sc50i-aids863-rr --pull=never --ulimit core=1 --cpus 2 --network none --user 1000:1000 \
	--mount "type=bind,src=$HERE,dst=/t,readonly" --mount "type=bind,src=$(cd "${R863_UPSTREAM:-$HERE/../../../../upstream}" && pwd -P),dst=/u,readonly" \
	--mount "type=bind,src=$OUT/bin,dst=/out" sc50i-rig:qt863-pub bash /t/build-aids.sh /out > "$OUT/bin/aids.txt" 2>&1
{ cat "$cid"; echo; } >> "$ROW863_CONTAINER_IDS"; rm -f "$cid"
docker run --rm --cidfile "$cid" --name sc50i-probe5-rr --pull=never --ulimit core=1 --cpus 2 \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
	--mount type=bind,src=/K3D/partners/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly \
	--mount "type=bind,src=$K/keys,dst=/run/keys,readonly" --mount "type=bind,src=$K/tools,dst=/tools,readonly" \
	--mount type=bind,src=/var/lib/sparky-lanes/sparky-repo-r1123a,dst=/repo,readonly \
	--mount "type=bind,src=$HERE,dst=/t,readonly" --mount "type=bind,src=$OUT/bin,dst=/out" sc50i-rig:a863-pubg \
	bash -c 'bash /t/build-probe-qt5.sh /out; rc=$?; chown 1000:1000 /out/* 2>/dev/null; exit $rc' > "$OUT/bin/probe-qt5.txt" 2>&1
{ cat "$cid"; echo; } >> "$ROW863_CONTAINER_IDS"; rm -f "$cid"
for f in r863-probe.so r863-probe-qt5.so gl-shim.so kubrick-shim-r863.so frame-check; do
	[ -s "$OUT/bin/$f" ] || { echo "the aid $f was not built (see $OUT/bin)"; exit 1; }
done
export PROBE_SO=$OUT/bin/r863-probe.so
bash "$HERE/a1.sh" "$OUT/a1" sc50i-rig:a863-pubg sc50i-rig:a863-q24
bash "$HERE/a2-a6.sh" "$OUT" sc50i-rig:a863-pubg sc50i-rig:a863-q24 | tee "$OUT/a2-a6.txt"
rc=0
python3 -I "$HERE/verdicts-a.py" "$OUT/a1" "$OUT/a2" "$OUT/a3" "$OUT/a4" "$OUT/a5" | tee "$OUT/verdicts.txt" || rc=1
grep -q "lag-selftest rc=0" "$OUT/a1/lag-selftest.txt" && echo "AS EXPECTED  lag.py's known bad cases: $(grep -c '^caught' "$OUT/a1/lag-selftest.txt") of 4 caught" \
	|| { echo "NOT AS EXPECTED  lag.py's known bad cases: $(tr '\n' ' ' < "$OUT/a1/lag-selftest.txt")"; rc=1; }
for v in pub q24; do
	line=$(grep -i '2D screen' "$OUT/a6/verdicts-$v.txt")
	case $line in PASS*) echo "AS EXPECTED  octave-xvfb-$v: $line" ;; *) echo "NOT AS EXPECTED  octave-xvfb-$v: ${line:-not run}"; rc=1 ;; esac
done
echo "load at end: $(cut -d' ' -f1-3 /proc/loadavg) ($(date -u +%TZ)); exit $rc"
exit $rc
