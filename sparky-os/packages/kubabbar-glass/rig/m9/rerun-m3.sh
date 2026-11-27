#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# rerun-m3.sh BEFORE AFTER OUT [CASE...]: Kubabbar Glass 9 milestone 3's proof (queue row 147, with row 945), from the
# packages installed in two proof rig images (the stereo-proof-rig's login-splash/mkrig.sh): BEFORE, the published round
# with milestone 2's stage and the portal packages the edition's image ships; AFTER, the same with this milestone's stage
# (gtk4 +stereo3d4, sparky-stereo-gtk, the family look, its menu bar, Kubabbar Glass 9) and the Stereo Browser. Every case
# runs on both images, into OUT/before and OUT/after; the rows the before image must fail are the red ones. Logins are
# fresh, each in a container of its own (login-splash/run-case.sh), KWin on the NVIDIA card through CDI, the session's
# programs on Mesa's software renderer. measure-m3.py writes the PASS and FAIL rows (OUT/summary.txt); exit 1 when one fails.
#   steppers         GTK 4's steppers in a real window from the installed library (gtk4-steppers.py, Xvfb)
#   gtk              the GTK 2, 3 and 4 galleries beside Qt 6's in both arrow placements, a Breeze control (gtk-proof.sh)
#   gtk-default      GTK 4's gallery in Breeze and in GTK's own theme: the other themes, unchanged (compared across images)
#   sync-test        the installed sparky-stereo-gtk-sync against tests/test_gtk_sync.py
#   bars             a login on Kubabbar Glass 9: GTK 3 and GTK 4 programs left alone, their bars (session3.py bars)
#   greeter-family-2d/3d  Kubabbar Glass's own SDDM theme in test mode, a Wayland window of the session, plain and per eye
#   dock-family, dock-9   a new account on the family's menu bar layout and on the 9's: the dock's launchers
# Env: DOCKER_HOST (your socket), NAME_PREFIX, RENDER_GROUP (default 125), BIN (fakeinput and gallery-gtk2 built for the
# image, default /var/lib/sparky-lanes/kubabbar-glass-9/work/bin), RIG (the stereo-proof-rig scripts).
set -uo pipefail
BEFORE=$1 AFTER=$2 OUT=$(mkdir -p "$3" && cd "$3" && pwd); shift 3
M9=$(cd "$(dirname "$0")" && pwd)
RECIPE=$(cd "$M9/../.." && pwd)
RIG=${RIG:-/K3D/GitHub/sparky-stereo-os/skills/stereo-proof-rig/scripts}
LT=${LT:-$(cd "$RIG/../../stereo-artwork/scripts/look-translucency" && pwd)}
BIN=${BIN:-/var/lib/sparky-lanes/kubabbar-glass-9/work/bin}
RC=$RIG/login-splash/run-case.sh
export NAME_PREFIX=${NAME_PREFIX:-kg9-m3} CARD=nvidia RENDER_GROUP=${RENDER_GROUP:-125}
CASES=("$@"); [ ${#CASES[@]} -gt 0 ] || CASES=(steppers gtk gtk-default sync-test bars greeter-family-2d greeter-family-3d dock-family dock-9)
base_mounts="$M9:/m9:ro $LT:/lt:ro $BIN:/bin2:ro"
common=(OUTPUTS=1 W=1920 H=1080 SETTLE=4 USER_SETUP=/rig-scripts/translucency-probe/user-setup.sh DESKTOP_PROBE=/m9/probe-m3.sh
	M9=/m9 LT=/lt FAKEINPUT=/bin2/fakeinput)
load() { echo "$(date -u +%FT%TZ) $1; load: $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$OUT/load.log"; }
contain() { # NAME IMAGE OUTDIR COMMAND...: a program of the rig's packages in a container of its own, as the person
	local name=$1 img=$2 o=$3; shift 3
	docker run --rm --init --name "$NAME_PREFIX-$name-$$" --ulimit core=1 --network none --cpus 4 --user "$(id -u):$(id -g)" \
		-e HOME=/tmp -e GTK2_GALLERY=/bin2/gallery-gtk2 --mount "type=bind,src=$M9,dst=/m9,readonly" \
		--mount "type=bind,src=$RECIPE,dst=/recipe,readonly" --mount "type=bind,src=$BIN,dst=/bin2,readonly" \
		--mount "type=bind,src=$o,dst=/out" "$img" "$@"
}
for side in before after; do
	img=$BEFORE; [ "$side" = after ] && img=$AFTER
	for c in "${CASES[@]}"; do
		load "$side case $c start"
		o=$OUT/$side/$c
		mkdir -p "$o"
		case $c in
			steppers) contain steppers "$img" "$o" bash /m9/x-run.sh python3 /m9/gtk4-steppers.py /out/steppers.json > "$o/steppers.log" 2>&1 ;;
			gtk) contain gtk "$img" "$o" bash /m9/gtk-proof.sh /out > "$o/gtk.log" 2>&1 ;;
			gtk-default) contain gtkdef "$img" "$o" bash -c 'for t in Breeze Default; do bash /m9/gtk-gallery.sh gtk4 "$t" "/out/gtk4-$t" > "/out/gtk4-$t-driver.txt" 2>&1; done' \
				> "$o/gtk-default.log" 2>&1 ;;
			sync-test) contain synctest "$img" "$o" python3 /recipe/tests/test_gtk_sync.py /usr/bin/sparky-stereo-gtk-sync /out/results > "$o/sync-test.log" 2>&1 ;;
			bars) RUN_MOUNTS="$base_mounts" bash "$RC" "$img" "$o" "${common[@]}" LOOK=kubabbar-glass-9 MODES=2d STEPS="bars" ;;
			greeter-family-2d|greeter-family-3d) RUN_MOUNTS="$base_mounts" bash "$RC" "$img" "$o" "${common[@]}" LOOK=kubabbar-glass \
				MODES=${c#greeter-family-} STEPS="greeter-family" ;;
			dock-family) RUN_MOUNTS="$base_mounts" bash "$RC" "$img" "$o" "${common[@]}" LOOK=kubabbar-glass-menubar MODES=2d \
				STEPS="dock panelshot:dock-shot" ;;
			dock-9) RUN_MOUNTS="$base_mounts" bash "$RC" "$img" "$o" "${common[@]}" LOOK=kubabbar-glass-9-menubar MODES=2d \
				STEPS="dock panelshot:dock-shot" ;;
			*) echo "unknown case $c" >&2 ;;
		esac
		echo "$side case $c exit $?" | tee -a "$OUT/load.log"
		load "$side case $c end"
	done
done
python3 "$M9/measure-m3.py" "$OUT" "$RIG" | tee "$OUT/summary.txt"
! grep -q '^FAIL' "$OUT/summary.txt"
