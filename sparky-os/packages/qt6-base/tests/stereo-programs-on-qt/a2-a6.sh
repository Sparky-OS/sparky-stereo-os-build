#!/bin/bash
# a2-a6.sh RESULTS PUB_IMAGE Q24_IMAGE -- row 863 part A, rows A2 to A6, one after the other (one container at a time):
#   films  VLC's own tests/mkclips2.py makes the marked 3D film (x264-fsbs.mp4) in a container of PUB_IMAGE
#   A2     a2.sh (VLC Stereo, the Qt 5 probe)
#   A3     a3.sh (Krita's stereo canvas layer) and its known bad case: the layer moved 40 px from the canvas widget
#          (the probe's "displace"), on the staged Qt, which Krita must place again and the measures must see
#   A4     a4.sh (Qt's own frame resized by its edge, and FC_STALE=1 as the known bad case)
#   A5     a5.sh (the installer's slideshow in a window of its own)
#   A6     a6-images.sh (an X server in the Octave image of step 5b, and the same with the staged Qt by qt-over.sh),
#          then the Octave rig's xvfb row on each, and verdicts_oct.py's line for it
# PROBE_SO: the r863-probe.so of build-aids.sh, with r863-probe-qt5.so, gl-shim.so and frame-check beside it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
UP=$(cd "${R863_UPSTREAM:-$HERE/../../../../upstream}" && pwd -P)
R=$1 PUB=$2 Q24=$3
L=/K3D/partners/queue/science-stereo-ship-and-upstream-50
export DOCKER_HOST=unix://$L/docker.sock ROW863_CONTAINER_IDS=${ROW863_CONTAINER_IDS:-$L/.container-ids}
mkdir -p "$R/films" "$R/files"
echo "start $(date -u +%TZ) load $(cut -d' ' -f1-3 /proc/loadavg)"
# the film, with VLC's own clip maker (build main sparky-os/upstream/vlc/vlc-stereo-packaging/tests/mkclips2.py)
if [ ! -s "$R/films/x264-fsbs.mp4" ]; then
	cid=$R/.cid-films; rm -f "$cid"
	docker run --rm --cidfile "$cid" --name sc50i-a863-films --pull=never --ulimit core=1 --cpus 4 --network none --user 1000:1000 \
		--mount "type=bind,src=$UP/vlc/vlc-stereo-packaging/tests,dst=/t,readonly" \
		--mount "type=bind,src=$R/films,dst=/out" "$PUB" python3 -I /t/mkclips2.py /out > "$R/films/mkclips2.log" 2>&1
	{ cat "$cid"; echo; } >> "$ROW863_CONTAINER_IDS"; rm -f "$cid"
fi
ls -la "$R/films" | grep mp4
bash "$HERE/a2.sh" "$R/a2" "$PUB" "$Q24" "$R/films"
# Krita's document: a side-by-side pair 1600x700 (at least twice as wide as high, as patch 0004 asks): a frame, a red
# disc 12 px to the right in the left eye and 12 px to the left in the right one (in front), a green bar in both
python3 -I - "$R/files/krita-pair.png" <<'PYDOC'
import sys
from PIL import Image, ImageDraw
w, h = 800, 700
img = Image.new('RGB', (2 * w, h), (40, 60, 90))
d = ImageDraw.Draw(img)
for eye, shift in ((0, 12), (1, -12)):
    x0 = eye * w
    d.rectangle([x0 + 40, 40, x0 + w - 40, h - 40], outline=(230, 230, 230), width=6)
    d.ellipse([x0 + 250 + shift, 200, x0 + 550 + shift, 500], fill=(220, 60, 50))
    d.rectangle([x0 + 100, 560, x0 + 300, 620], fill=(60, 200, 90))
img.save(sys.argv[1])
PYDOC
bash "$HERE/a3.sh" "$R/a3" "$PUB" "$Q24" "$R/files"
FILES=$R/files bash "$HERE/run-prog.sh" bad-krita-q24 "$Q24" "$R/a3" R863_WATCH=KisOpenGLCanvas2 R863_LAYER=1 \
	'PRESETUP=mkdir -p $XDG_CONFIG_HOME && printf "stereo3DCanvas=true\n" > $XDG_CONFIG_HOME/kritadisplayrc' \
	"PROG=/usr/bin/krita --nosplash /files/krita-pair.png" "R863_STEPS=displace,wait" \
	R863_START=45000 R863_WAIT=60 R863_QUIT=1 CASE_TIMEOUT=240 > /dev/null
python3 -I "$HERE/analyze-prog.py" "$R/a3/bad-krita-q24" > "$R/a3/bad-krita-q24.json"
bash "$HERE/a4.sh" "$R/a4" "$PUB" "$Q24"
bash "$HERE/a5.sh" "$R/a5" "$PUB" "$Q24"
# A6
R863_WORK=$R/a6 bash "$HERE/a6-images.sh" sc50i-rig:oct863-pkg-doc2 sc50i-rig:a863-oct-x > "$R/a6-image-pub.txt" 2>&1
tail -1 "$R/a6-image-pub.txt"
S=/var/lib/sparky-lanes/qt-flush-863/parta/stage-debs
[ -d "$S" ] || S=/var/tmp/qt-flush-863/parta/stage-debs
R863_WORK=$R/a6 bash /var/lib/sparky-lanes/qt-flush-863/kit/tools/qt-over.sh sc50i-rig:a863-oct-x sc50i-rig:a863-oct-x24 "$S" > "$R/a6-image-q24.txt" 2>&1
tail -1 "$R/a6-image-q24.txt"
K=/var/lib/sparky-lanes/science-50i/kept-octave
for v in pub q24; do
	img=sc50i-rig:a863-oct-x; [ $v = q24 ] && img=sc50i-rig:a863-oct-x24
	RIGDIR=$K/rig PROOFRIG=$K/proofrig RUNS=$R/a6/runs-$v bash "$K/rig/rows.sh" p "$img" xvfb > "$R/a6/rows-$v.txt" 2>&1
	python3 -I "$K/rig/verdicts_oct.py" "$R/a6/runs-$v" p > "$R/a6/verdicts-$v.txt" 2>&1
	echo "A6 $v: $(grep -i '2D screen' "$R/a6/verdicts-$v.txt")"
done
echo "end $(date -u +%TZ) load $(cut -d' ' -f1-3 /proc/loadavg)"
