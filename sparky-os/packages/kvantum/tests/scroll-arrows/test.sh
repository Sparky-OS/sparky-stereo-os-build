#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# Inside a throwaway Debian testing container, as root: install a Kvantum build (the .deb files given, or Debian's when
# none are), build probe.cpp for Qt 6 and Qt 5, and measure where the scroll arrows are with a theme that sets
# scroll_arrows_together=true and one that does not. Usage: test.sh OUT EXPECT [DEB...]
#   EXPECT=together  the key works: both arrows at the end, the groove from the start, presses hit their arrow
#   EXPECT=ignored   the key is not known (Debian's build): the arrows stay at both ends; the red control
# Results: OUT/probe-{qt6,qt5}-{together,apart}.json and OUT/verdict.txt; exit 0 only when every row is as EXPECT says.
set -euo pipefail
OUT=$1; EXPECT=$2; shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
export DEBIAN_FRONTEND=noninteractive
mkdir -p "$OUT"
if [ -d /repo/dists/mashtabba ]; then
	# the edition's published tree, as the build saw it (its Qt is the edition's)
	printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
	printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
fi
apt-get -y update > "$OUT/apt-update.log" 2>&1
pkgs="g++ pkgconf qt6-base-dev qtbase5-dev python3 xauth"
if [ $# -gt 0 ]; then
	apt-get -y --no-install-recommends install $pkgs "$@" > "$OUT/apt-install.log" 2>&1
else
	apt-get -y --no-install-recommends install $pkgs qt-style-kvantum > "$OUT/apt-install.log" 2>&1
fi
dpkg-query -W -f '${Package} ${Version}\n' qt-style-kvantum qt6-base-dev qtbase5-dev > "$OUT/versions.txt"
work=$(mktemp -d)
g++ -std=c++17 -fPIC -o "$work/probe-qt6" "$HERE/probe.cpp" $(pkg-config --cflags --libs Qt6Widgets)
g++ -std=c++17 -fPIC -o "$work/probe-qt5" "$HERE/probe.cpp" $(pkg-config --cflags --libs Qt5Widgets)
for theme in together apart; do
	cfg=$work/config-$theme
	mkdir -p "$cfg/Kvantum/Probe"
	printf '[General]\ntheme=Probe\n' > "$cfg/Kvantum/kvantum.kvconfig"
	{
		printf '[%%General]\nscroll_width=16\nscroll_arrows=true\n'
		[ "$theme" = together ] && printf 'scroll_arrows_together=true\n'
		true
	} > "$cfg/Kvantum/Probe/Probe.kvconfig"
	for qt in qt6 qt5; do
		XDG_CONFIG_HOME=$cfg QT_QPA_PLATFORM=offscreen "$work/probe-$qt" > "$OUT/probe-$qt-$theme.json"
	done
done
python3 - "$OUT" "$EXPECT" <<'PY'
import json, pathlib, sys
out, expect = pathlib.Path(sys.argv[1]), sys.argv[2]
a = 16
want_apart = {
    "vertical": {"subline": [0, 0, a, a], "addline": [0, 200 - a, a, a], "groove": [0, a, a, 200 - 2 * a]},
    "horizontal": {"subline": [0, 0, a, a], "addline": [200 - a, 0, a, a], "groove": [a, 0, 200 - 2 * a, a]},
    "horizontal_rtl": {"subline": [200 - a, 0, a, a], "addline": [0, 0, a, a], "groove": [a, 0, 200 - 2 * a, a]},
}
want_together = {
    "vertical": {"subline": [0, 200 - 2 * a, a, a], "addline": [0, 200 - a, a, a], "groove": [0, 0, a, 200 - 2 * a]},
    "horizontal": {"subline": [200 - 2 * a, 0, a, a], "addline": [200 - a, 0, a, a], "groove": [0, 0, 200 - 2 * a, a]},
    "horizontal_rtl": {"subline": [a, 0, a, a], "addline": [0, 0, a, a], "groove": [2 * a, 0, 200 - 2 * a, a]},
}
rows, bad = [], 0
for qt in ("qt6", "qt5"):
    for theme in ("together", "apart"):
        got = json.loads((out / f"probe-{qt}-{theme}.json").read_text())
        want = want_together if (theme == "together" and expect == "together") else want_apart
        for bar, parts in want.items():
            g = got[bar]
            ok = g["extent"] == a and all(g[k] == v for k, v in parts.items())
            ok = ok and g["hit_subline"] == "subline" and g["hit_addline"] == "addline"
            # the slider and the pages stay inside the groove
            gx, gy, gw, gh = g["groove"]
            for part in ("slider", "subpage"):
                x, y, w, h = g[part]
                if bar.startswith("horizontal") and not bar.endswith("rtl"):
                    ok = ok and gx <= x and x + w <= gx + gw
                elif bar == "vertical":
                    ok = ok and gy <= y and y + h <= gy + gh
            bad += not ok
            rows.append(f"{'PASS' if ok else 'FAIL'} {qt} theme={theme} {bar}: subline {g['subline']} addline {g['addline']} groove {g['groove']} slider {g['slider']} hits {g['hit_subline']}/{g['hit_addline']}")
verdict = "\n".join(rows) + f"\n{len(rows) - bad} of {len(rows)} rows as expected ({expect})\n"
(out / "verdict.txt").write_text(verdict)
print(verdict, end="")
sys.exit(1 if bad else 0)
PY
