#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# rerun-m2.sh IMAGE OUT [CASE...]: Kubabbar Glass 9 milestone 2's proof, from the packages installed in a proof rig image
# (the stereo-proof-rig's login-splash/mkrig.sh, with the stage's packages). Every case is a fresh login in a container of
# its own (login-splash/run-case.sh), KWin on the NVIDIA card through CDI, the session's programs on Mesa's software
# renderer; then measure-m2.py turns the results into PASS and FAIL rows (OUT/summary.txt); exit 1 when one fails.
#   gtk           the GTK 2, 3 and 4 galleries beside Qt 6's, both arrow placements, a Breeze control (gtk-proof.sh)
#   menubar-2d/3d a new account on the menu bar layout: its panels and applets, their glass; per eye on a 3D output
#   keep          an account with its own panels: the menu bar look applied without and with the layout
#   splash-2d/3d  the loading screen, plain and per eye
#   splash-black/white  the loading screen over a black and a white background: its box's glass read back
#   greeter-2d/3d the login screen (SDDM's greeter in test mode, a Wayland window): the window, then the password box;
#                 measured over a noise picture in the pattern's place (greeter-3d-look: the real pattern, for looking)
#   qt5-carry     a Qt 5 program with the edition's Qt 5 platform theme (row 59's carry), and the GTK themes the session loads
#   qt5-nocarry   the same with the platform theme hidden (red: Qt 5 alone does not take the look)
# Env: DOCKER_HOST (your socket), NAME_PREFIX, RENDER_GROUP (default 125), BIN (a folder with fakeinput and gallery-gtk2
# built for the image, default /var/lib/sparky-lanes/kubabbar-glass-9/work/bin), RIG (the stereo-proof-rig scripts).
set -uo pipefail
IMG=$1 OUT=$(mkdir -p "$2" && cd "$2" && pwd); shift 2
M9=$(cd "$(dirname "$0")" && pwd)
RIG=${RIG:-/K3D/GitHub/sparky-stereo-os/skills/stereo-proof-rig/scripts}
LT=${LT:-$(cd "$RIG/../../stereo-artwork/scripts/look-translucency" && pwd)}
BIN=${BIN:-/var/lib/sparky-lanes/kubabbar-glass-9/work/bin}
RC=$RIG/login-splash/run-case.sh
export NAME_PREFIX=${NAME_PREFIX:-kg9-m2} CARD=nvidia RENDER_GROUP=${RENDER_GROUP:-125}
CASES=("$@"); [ ${#CASES[@]} -gt 0 ] || CASES=(gtk menubar-2d menubar-3d keep splash-2d splash-3d splash-black splash-white greeter-2d greeter-3d greeter-3d-look qt5-carry qt5-nocarry)
fix=$OUT/fixtures; mkdir -p "$fix/empty"
python3 - "$fix" <<'PY'
import sys
import numpy as np
from PIL import Image
d = sys.argv[1]
Image.new("RGB", (1920, 1080), (0, 0, 0)).save(f"{d}/black.png")
Image.new("RGB", (1920, 1080), (255, 255, 255)).save(f"{d}/white.png")
# an aperiodic texture in the pattern's place, so the sunk layer's shift is measurable (the woven pattern is nearly flat)
rng = np.random.default_rng(147)
noise = rng.integers(0, 256, size=(270, 480, 3), dtype=np.uint8)
Image.fromarray(noise).resize((1920, 1080), Image.NEAREST).save(f"{d}/noise.png")
PY
base_mounts="$M9:/m9:ro $LT:/lt:ro $BIN:/bin2:ro"
common=(OUTPUTS=1 W=1920 H=1080 SETTLE=4 USER_SETUP=/rig-scripts/translucency-probe/user-setup.sh DESKTOP_PROBE=/m9/probe-m2.sh
	M9=/m9 LT=/lt GTK2_GALLERY=/bin2/gallery-gtk2 FAKEINPUT=/bin2/fakeinput)
splash_bg=/usr/share/plasma/look-and-feel/kubabbar-glass-9/contents/splash/images/background.png
wall=/usr/share/wallpapers/kubabbar-glass-9/contents/images/1920x1080.png
load() { echo "$(date -u +%FT%TZ) $1; load: $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$OUT/load.log"; }
for c in "${CASES[@]}"; do
	load "case $c start"
	o=$OUT/$c
	case $c in
		gtk) mkdir -p "$o"; docker run --rm --name "$NAME_PREFIX-gtk-$$" --ulimit core=1 --network none --cpus 4 --user "$(id -u):$(id -g)" \
			-e GTK2_GALLERY=/bin2/gallery-gtk2 --mount "type=bind,src=$M9,dst=/m9,readonly" \
			--mount "type=bind,src=$BIN,dst=/bin2,readonly" --mount "type=bind,src=$o,dst=/out" "$IMG" bash /m9/gtk-proof.sh /out > "$OUT/gtk.log" 2>&1 ;;
		menubar-2d) RUN_MOUNTS="$base_mounts" bash "$RC" "$IMG" "$o" "${common[@]}" LOOK=kubabbar-glass-9-menubar MODES=2d STEPS="panels:panels panelshot:panels-shot glass" ;;
		menubar-3d) RUN_MOUNTS="$base_mounts" bash "$RC" "$IMG" "$o" "${common[@]}" LOOK=kubabbar-glass-9-menubar MODES=3d STEPS="panels:panels panelshot:panels-shot" ;;
		keep) RUN_MOUNTS="$base_mounts" bash "$RC" "$IMG" "$o" "${common[@]}" LOOK=kubabbar-glass-9 MODES=2d STEPS="keep" ;;
		splash-2d) RUN_MOUNTS="$base_mounts" bash "$RC" "$IMG" "$o" "${common[@]}" LOOK=kubabbar-glass-9 MODES=2d HOLD=8 SHOTS="3 5" STEPS="panels:panels" ;;
		splash-3d) RUN_MOUNTS="$base_mounts" bash "$RC" "$IMG" "$o" "${common[@]}" LOOK=kubabbar-glass-9 MODES=3d HOLD=8 SHOTS="3 5" STEPS="panels:panels" ;;
		splash-black|splash-white) RUN_MOUNTS="$base_mounts $fix/${c#splash-}.png:$splash_bg:ro" bash "$RC" "$IMG" "$o" "${common[@]}" \
			LOOK=kubabbar-glass-9 MODES=2d HOLD=8 SHOTS="3" STEPS="panels:panels" ;;
		greeter-2d|greeter-3d) RUN_MOUNTS="$base_mounts $fix/noise.png:$wall:ro" bash "$RC" "$IMG" "$o" "${common[@]}" \
			LOOK=kubabbar-glass-9 MODES=${c#greeter-} STEPS="greeter" ;;
		greeter-3d-look) RUN_MOUNTS="$base_mounts" bash "$RC" "$IMG" "$o" "${common[@]}" LOOK=kubabbar-glass-9 MODES=3d STEPS="greeter" ;;
		qt5-carry) RUN_MOUNTS="$base_mounts" bash "$RC" "$IMG" "$o" "${common[@]}" LOOK=kubabbar-glass-9 MODES=2d STEPS="qt5 gtk" ;;
		qt5-nocarry) RUN_MOUNTS="$base_mounts $fix/empty:/usr/lib/x86_64-linux-gnu/qt5/plugins/platformthemes:ro" bash "$RC" "$IMG" "$o" \
			"${common[@]}" LOOK=kubabbar-glass-9 MODES=2d STEPS="qt5" ;;
		*) echo "unknown case $c" >&2 ;;
	esac
	echo "case $c exit $?" | tee -a "$OUT/load.log"
	load "case $c end"
done
python3 "$M9/measure-m2.py" "$OUT" "$RIG" | tee "$OUT/summary.txt"
! grep -q '^FAIL' "$OUT/summary.txt"
