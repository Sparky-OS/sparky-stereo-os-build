#!/bin/bash
# Sparky Stereo OS: the CSS colour test of ORDER 348. Renders a corpus of SVGs (every colour syntax and space of CSS
# Color 4, CSS Color 5 and CSS Color HDR, each as a fill and as a gradient, plus ramps and a 16-bit step wedge) with Qt
# SVG into deep QImage formats and with librsvg into cairo's RGBA128F, and compares each stored value with the value
# the specifications' own sample code gives (ref.py), at the precision CSS Color 4 sections 16.2 to 16.5 and CSS
# Color HDR section 10.1 set.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Usage: test.sh RENDERER DEB_DIR RESULTS   (RENDERER: qt or rsvg, the one whose lines decide the exit status;
#   DEB_DIR: a folder holding a build's .deb files, installed over Debian testing's, or the word debian for Debian's
#   own packages, the control; RESULTS: an empty folder). Exit 0 when no value of that renderer fails; a LIMIT line
#   names the layer beneath the renderer that holds less (QPainter's gradients, cairo) and counts as a pass of the
#   renderer. Debian's qt6-svg 6.11.2-2 and librsvg 2.63.3+dfsg-1 fail it: they draw these colours black.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=debian@sha256:fe4be93b807e7d05dccdaf54931173d9368b349f91a8170dadd787213aa3bf19
RENDERER=$1
RESULTS=$(mkdir -p "$3" && cd "$3" && pwd)
[ -z "$(ls -A "$RESULTS")" ] || { echo "$RESULTS is not empty" >&2; exit 1; }
case $RENDERER in qt|rsvg) ;; *) echo "RENDERER is qt or rsvg" >&2; exit 2 ;; esac
python3 -I "$HERE/make_corpus.py" "$RESULTS/corpus" >/dev/null
MOUNTS=()
if [ "$2" != debian ]; then
	MOUNTS=(-v "$(cd "$2" && pwd)":/debs:ro)
fi
mkdir "$RESULTS/out"
# the edition sits on deb-multimedia (the edition's librsvg links its dav1d), so the test image has it too
docker run --rm --cpus 4 --platform linux/amd64 "${MOUNTS[@]}" -v "$RESULTS/corpus":/corpus:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v "$RESULTS/out":/out "$IMAGE" bash /tools/test-in-container.sh
fails=$(grep -c "^FAIL .* $RENDERER:" "$RESULTS/out/compare.txt" || true)
echo "$RENDERER: $fails failing values" | tee "$RESULTS/summary.txt"
grep "^$RENDERER:" "$RESULTS/out/summary.txt" | tee -a "$RESULTS/summary.txt"
[ "$fails" = 0 ]
