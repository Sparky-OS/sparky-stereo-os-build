#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# rerun.sh IMAGE OUT [--with-installed-fonts]: every proof of Kubabbar Glass 9 again, from the packages installed in
# IMAGE, a stereo-proof-rig image (login-splash/mkrig.sh) made from a publication round with the stage's .debs added:
#   1  the session helper's tests (tests/test_glass9_sync.py): green on the shipped helper, red on a copy that writes the
#      person's own kdeglobals
#   2  the font route through plasma-apply-lookandfeel (lnf-fonts.sh): its red and green rows
#   3  the galleries, Kubabbar Glass 9 beside Kubabbar Glass, Qt 6 and Qt 5 (gallery-compare.sh)
#   4  fresh logins (the rig's login-splash/run-case.sh, KWin on the NVIDIA card): the glass and a desktop widget;
#      the programs in 2D; the programs per eye on a 3D output; the fonts with only the free fallbacks; with
#      --with-installed-fonts also the fonts with /usr/local/share/fonts mounted read-only (nothing is copied out)
#   5  the measurements (measure9.py): every glass level against Kubabbar Glass 20261126, each window's depth
# Ends with one line per row, PASS or FAIL, and exits 1 when a row fails.
# Env: DOCKER_HOST (your own socket), NAME_PREFIX (default kg9), RIG (stereo-proof-rig's scripts folder),
#      LT (stereo-artwork's look-translucency scripts), RENDER_GROUP (the NVIDIA render node's group in a container,
#      default 125), CARD (default nvidia; empty for the render node RENDER_NODE).
set -uo pipefail
IMG=${1:?image}; OUT=$(mkdir -p "${2:?output folder}" && cd "$2" && pwd)
INSTALLED_FONTS=0; [ "${3:-}" = --with-installed-fonts ] && INSTALLED_FONTS=1
M9=$(cd "$(dirname "$0")" && pwd)
REC=$(cd "$M9/../.." && pwd)
P=${NAME_PREFIX:-kg9}
RIG=${RIG:-/K3D/GitHub/sparky-stereo-os/skills/stereo-proof-rig/scripts}
LT=${LT:-/K3D/GitHub/sparky-stereo-os/skills/stereo-artwork/scripts/look-translucency}
rows=()
row() { rows+=("$1 $2"); }
load() { echo "$(date -u +%FT%TZ) $1; load: $(cut -d' ' -f1-3 /proc/loadavg)" >> "$OUT/load.log"; }
run() { docker run --rm --ulimit core=1 --network none --cpus 2 --user "$(id -u):$(id -g)" -e HOME=/tmp -e LANG=C.UTF-8 "$@"; }

load "start"
# 1 the helper, green and red
mkdir -p "$OUT/sync" "$OUT/sync-red" "$OUT/red-bin/lang"
cp "$REC/bin/kubabbar-glass-9-sync" "$REC/bin/kubabbar-glass-9-scrolling" "$OUT/red-bin/"
cp -r "$REC/lang/scrolling9" "$OUT/red-bin/lang/"
sed -i 's|write "$defaults/kdeglobals" General font "$system"|write "$config/kdeglobals" General font "$system"|' "$OUT/red-bin/kubabbar-glass-9-sync"
run --name "$P-rerun-sync" --mount "type=bind,src=$REC,dst=/r,readonly" --mount "type=bind,src=$OUT,dst=/out" "$IMG" \
	python3 /r/tests/test_glass9_sync.py /r/bin /out/sync > "$OUT/sync.txt" 2>&1
row "$([ $? = 0 ] && echo PASS || echo FAIL)" "helper tests, shipped helper (all cases pass)"
run --name "$P-rerun-sync-red" --mount "type=bind,src=$REC,dst=/r,readonly" --mount "type=bind,src=$OUT/red-bin,dst=/redbin,readonly" \
	--mount "type=bind,src=$OUT,dst=/out" "$IMG" python3 /r/tests/test_glass9_sync.py /redbin /out/sync-red > "$OUT/sync-red.txt" 2>&1
row "$([ $? != 0 ] && echo PASS || echo FAIL)" "helper tests, red: a helper that writes the person's file fails them"
# 2 the font route
run --name "$P-rerun-lnf" --mount "type=bind,src=$M9,dst=/m9,readonly" --mount "type=bind,src=$OUT,dst=/out" "$IMG" \
	bash /m9/lnf-fonts.sh /out/lnf-fonts > "$OUT/lnf-fonts.txt" 2>/dev/null
row "$([ $? = 0 ] && echo PASS || echo FAIL)" "font route: a look carrying fonts removes the person's (red row holds), the 9 keeps them"
# 3 the galleries
run --name "$P-rerun-gallery" --mount "type=bind,src=$M9,dst=/m9,readonly" --mount "type=bind,src=$OUT,dst=/out" "$IMG" \
	bash /m9/gallery-compare.sh /out/gallery > "$OUT/gallery.txt" 2>&1
n=$(ls "$OUT"/gallery/*-qt[56].png 2>/dev/null | wc -l)
row "$([ "$n" = 4 ] && echo PASS || echo FAIL)" "galleries: Kubabbar Glass 9 and Kubabbar Glass, Qt 6 and Qt 5 ($n of 4 pictures)"
load "tests end"
# 4 fresh logins
export NAME_PREFIX="$P-case" CARD=${CARD-nvidia} RENDER_GROUP=${RENDER_GROUP:-125}
mounts="$M9:/m9:ro $LT:/lt:ro"
common=(OUTPUTS=1 W=1920 H=1080 SHOTS=1 SETTLE=4 USER_SETUP=/rig-scripts/translucency-probe/user-setup.sh LOOK=kubabbar-glass-9
	DESKTOP_PROBE=/m9/probe9.sh M9=/m9 LT=/lt)
cases="glass apps-2d apps-3d fonts-free"; [ "$INSTALLED_FONTS" = 1 ] && cases="$cases fonts-installed"
for c in $cases; do
	load "case $c start"
	case $c in
		glass) RUN_MOUNTS="$mounts" bash "$RIG/login-splash/run-case.sh" "$IMG" "$OUT/$c" "${common[@]}" MODES=2d STEPS="glass widget" ;;
		apps-2d) RUN_MOUNTS="$mounts" bash "$RIG/login-splash/run-case.sh" "$IMG" "$OUT/$c" "${common[@]}" MODES=2d STEPS="apps fonts" ;;
		apps-3d) RUN_MOUNTS="$mounts" bash "$RIG/login-splash/run-case.sh" "$IMG" "$OUT/$c" "${common[@]}" MODES=3d STEPS="apps" ;;
		fonts-free) RUN_MOUNTS="$mounts" bash "$RIG/login-splash/run-case.sh" "$IMG" "$OUT/$c" "${common[@]}" MODES=2d STEPS="apps fonts" APPS="dolphin konsole gallery-qt6" ;;
		fonts-installed) RUN_MOUNTS="$mounts /usr/local/share/fonts:/usr/local/share/fonts:ro" bash "$RIG/login-splash/run-case.sh" "$IMG" "$OUT/$c" "${common[@]}" MODES=2d STEPS="apps fonts" APPS="dolphin konsole gallery-qt6" ;;
	esac > "$OUT/case-$c.txt" 2>&1
	row "$([ $? = 0 ] && echo PASS || echo FAIL)" "login $c ran"
	load "case $c end"
done
# 5 the measurements
python3 -I "$M9/measure9.py" glass "$OUT/glass" > "$OUT/glass-measured.txt" 2>&1
python3 -I "$M9/measure9.py" depth "$OUT/apps-3d" > "$OUT/depth.txt" 2>&1
python3 -I - "$OUT" "$INSTALLED_FONTS" > "$OUT/rows.txt" <<'PY'
import ast, json, os, sys
out, installed = sys.argv[1], sys.argv[2] == "1"
def lines(name):
    p = os.path.join(out, name)
    return [ast.literal_eval(l) for l in open(p) if l.startswith("{")] if os.path.exists(p) else []
g = lines("glass-measured.txt")
for r in g:
    if "equal" in r:
        print(("PASS" if r["equal"] else "FAIL"), "glass %s: %s, Kubabbar Glass 20261126 %s" % (r["surface"], r["measured"], r["kubabbar_glass_20261126"]))
    elif r.get("surface") == "probe-active":
        print(("PASS" if r.get("measured") is None else "FAIL"), "glass the active window: opaque")
if not g:
    print("FAIL glass: no measurement")
d = [r for r in lines("depth.txt") if "disparity" in r]
act = [r for r in d if r["active"]]
back = [r for r in d if not r["active"] and not r["dock"]]
print(("PASS" if act and all(r["disparity"] == 0 and r["residual"] < 1 for r in act) else "FAIL"),
      "depth: the active window on the screen plane", [(r["class"], r["disparity"], r["residual"]) for r in act])
print(("PASS" if back and all(0 < r["disparity"] <= 10 and r["residual"] < 2 for r in back) else "FAIL"),
      "depth: the windows behind sunk, within the default limit of 10", [(r["class"], r["disparity"], r["residual"]) for r in back])
for c, want in (("fonts-free", "Noto Sans Display"), ("fonts-installed", "Charcoal")):
    p = os.path.join(out, c, "fonts.json")
    if c == "fonts-installed" and not installed:
        continue
    f = json.load(open(p)) if os.path.exists(p) else {}
    q = f.get("qt6", {})
    ok = all(q.get(k, {}).get("drawn") == want for k in ("GeneralFont", "TitleFont", "QMenu")) and q.get("style") == "kvantum"
    if c == "fonts-installed" and not f.get("installed-classic", {}).get("Charcoal"):
        ok, want = False, want + " (not installed on this machine)"
    print(("PASS" if ok else "FAIL"), "%s: Qt 6 system, title and menu fonts drawn in %s, style kvantum" % (c, want),
          {k: q.get(k, {}).get("drawn") for k in ("GeneralFont", "FixedFont", "SmallestReadableFont", "QToolButton")})
PY
load "end"
printf '%s\n' "${rows[@]}" | cat - "$OUT/rows.txt" | tee "$OUT/summary.txt"
! grep -q '^FAIL' "$OUT/summary.txt"
