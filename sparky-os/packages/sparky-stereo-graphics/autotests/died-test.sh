#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ORDER 467: a program sent to a GPU that stops right after it starts is told and kept (Daniel, 2026-11-01: "either it
# works or not and the user must know"), and a program that did nothing wrong is not. Black box against a stand-in for
# the session's systemd (fake-systemd.py) on a private bus: sparky-stereo-gpu-env --died and --survived are what the
# session's systemd runs for an application's service (share/systemd/user). BIN: sparky-stereo-gpu-env, makefixture.
# SRC: the package source. Without the --died option every case fails (red), with it they pass (green).
set -u
BIN=${BIN:?}
SRC=${SRC:?}
T=$(mktemp -d)
trap 'kill $SD $BUS 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"; [ -z "${KEEP:-}" ] || echo "kept $T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
has() { if grep -qF -- "$3" "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: '$3' not in: $(head -c 700 "$2")"; fi; }
"$BIN/makefixture" host "$T/host" || exit 1
export XDG_CONFIG_HOME=$T/config XDG_CONFIG_DIRS=$T/none XDG_DATA_HOME=$T/data XDG_DATA_DIRS=$T/usr XDG_STATE_HOME=$T/state
export SPARKY_STEREO_GRAPHICS_ROOT=$T/host SPARKY_STEREO_POWER_PROFILE=performance LANG=C.UTF-8
unset LANGUAGE LC_ALL LC_MESSAGES WAYLAND_DISPLAY DISPLAY DRI_PRIME MESA_VK_DEVICE_SELECT VK_LOADER_DRIVERS_SELECT __NV_PRIME_RENDER_OFFLOAD
mkdir -p "$XDG_CONFIG_HOME" "$T/none" "$T/usr/applications" "$T/data/applications"
printf '[Desktop Entry]\nType=Application\nName=Sparky Browser\nExec=true\nCategories=Network;WebBrowser;\n' >"$T/usr/applications/sparky-browser.desktop"
printf '[Desktop Entry]\nType=Application\nName=Editor\nExec=true\nCategories=Utility;TextEditor;\n' >"$T/usr/applications/editor.desktop"
PROBLEMS=$XDG_STATE_HOME/sparky-stereo-problems
rec() { echo "$PROBLEMS/sparky-stereo-graphics_died-$1.json"; }
field() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>&1; }
sparky-stereo-problems catalog sparky-stereo-graphics "$SRC/po" "$T/catalog" --domain kcm_sparkystereo_graphics \
	--context "@info" --context "@item kind of program" --context "@action:button" \
	--subject "@title notification|A graphics choice cannot be used" \
	--subject-map '{"@info %1 is a program, %2 a GPU name, %3 says how it stopped|%1 stopped right after it started on %2: %3.": "@title notification|A program stopped on its GPU"}' >/dev/null || exit 1
export SPARKY_STEREO_PROBLEMS_CATALOG=$T/catalog:/usr/lib/systemd/catalog
# what KIO gives a browser on the performance profile: the lines sparky-stereo-gpu-env prints, in the unit's Environment
ROUTE=$("$BIN/sparky-stereo-gpu-env" --app "$T/usr/applications/sparky-browser.desktop" --profile performance)
[ -n "$ROUTE" ] || { echo "no route for the browser"; exit 1; }
env_json=$(python3 -I -c 'import json,sys; print(json.dumps(sys.stdin.read().split()))' <<<"$ROUTE")
B=$T/usr/applications/sparky-browser.desktop
ED=$T/usr/applications/editor.desktop
# one unit per case: app-NAME@ID.service as KIO names it (the name escaped by systemd: a dash is \x2d)
python3 -I - "$T/units.json" "$B" "$ED" "$env_json" <<'PY'
import json, sys
out, b, ed, env = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
def esc(n): return n.replace("-", "\\x2d")
def unit(name, ident, src, ran, result, status, e, start=100):
    return ("app-%s@%s.service" % (esc(name), ident), {"SourcePath": src, "start": start, "ran": ran, "Result": result, "Status": status, "Environment": e})
cases = [
    ("sparky-browser", "a1", b, 3.2, "core-dump", 11, env),
    ("exits1", "a2", b, 0.4, "exit-code", 1, env),
    ("launcher", "a3", b, 0.2, "success", 0, env),
    ("killed", "a4", b, 2, "signal", 9, env),
    ("late", "a5", b, 3600, "core-dump", 11, env),
    ("unrouted", "a6", b, 1, "core-dump", 11, ["PATH=/usr/bin"]),
    ("editor", "a7", ed, 1, "core-dump", 11, ["PATH=/usr/bin"]),
    ("nodesktop", "a8", "", 1, "core-dump", 11, env),
    ("timeout", "a9", b, 2, "timeout", 0, env),
    ("longlived", "b1", b, 600, "success", 0, env),
    ("exits1", "b2", b, 600, "success", 0, env),
    ("exits1", "b3", b, 0.2, "success", 0, env),
    ("sparky-browser", "b4", b, 3, "signal", 15, env),
]
units = dict(unit(*c) for c in cases)
units["sparky-stereo-gpu-died@x.service"] = {"SourcePath": b, "start": 100, "ran": 1, "Result": "core-dump", "Status": 11, "Environment": env}
json.dump(units, open(out, "w"))
PY
U() { echo "app-${1//-/\\x2d}@$2.service"; }
cat >"$T/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=$T/bus</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
CONF
dbus-daemon --config-file="$T/bus.conf" --nofork >"$T/bus.log" 2>&1 &
BUS=$!
for _ in $(seq 1 50); do [ -S "$T/bus" ] && break; sleep 0.1; done
export DBUS_SESSION_BUS_ADDRESS="unix:path=$T/bus"
python3 -I "$SRC/autotests/fake-systemd.py" "$T/units.json" >"$T/sd.log" 2>&1 &
SD=$!
for _ in $(seq 1 50); do grep -q ready "$T/sd.log" && break; sleep 0.1; done
grep -q ready "$T/sd.log" || { cat "$T/sd.log"; exit 1; }
died() { "$BIN/sparky-stereo-gpu-env" --died "$1" >"$T/out" 2>"$T/err"; echo $?; }
survived() { "$BIN/sparky-stereo-gpu-env" --survived "$1" >"$T/out" 2>"$T/err"; echo $?; }
kept() { ls "$PROBLEMS"/sparky-stereo-graphics_died-* 2>/dev/null | wc -l; }
clean() { rm -f "$PROBLEMS"/sparky-stereo-graphics_died-*; }

echo "== a program sent to the NVIDIA card that crashes 3 seconds after it started"
check "a crash at start: exit 0" "$(died "$(U sparky-browser a1)")" 0
has "a crash at start: said" "$T/err" "Sparky Browser stopped right after it started on NVIDIA GeForce RTX 3060 Lite Hash Rate: it crashed (signal 11)."
check "a crash at start: one record" "$(kept)" 1
R=$PROBLEMS/sparky-stereo-graphics_died-sparky-browser.json
check "a crash at start: kept under the program's name, \x2d read as a dash" "$([ -e "$R" ] && echo 0 || echo 1)" 0
check "a crash at start: the record's kind" "$(field "$R" 'd["data"]["kind"]')" "app-died"
check "a crash at start: the GPU it died on" "$(field "$R" 'd["data"]["requested"]')" "pci-0000:01:00.0"
check "a crash at start: Use NAME is the desktop's GPU, for this program only" "$(field "$R" '[a["command"] for a in d["actions"] if a["id"].startswith("use:")]')" "[['sparky-stereo-gpu-env', '--use-app', 'sparky-browser.desktop', 'pci-0000:0b:00.0']]"
check "a crash at start: and Open Graphics settings" "$(field "$R" '[a["id"] for a in d["actions"]]')" "['use:pci-0000:0b:00.0', 'open']"
check "the program is never started again by the engine: the record has no repair" "$(field "$R" 'd["repair"]')" "[]"
echo "== the notice in the person's language"
sparky-stereo-problems list >"$T/list" 2>&1
has "listed in English" "$T/list" "Sparky Browser stopped right after it started on NVIDIA GeForce RTX 3060 Lite Hash Rate: it crashed (signal 11)."
LANG=de_DE.UTF-8 LANGUAGE=de sparky-stereo-problems list >"$T/list" 2>&1
has "listed in German, with the title" "$T/list" "Ein Programm ist auf seiner GPU angehalten"
has "listed in German" "$T/list" "Sparky Browser wurde kurz nach dem Start auf NVIDIA GeForce RTX 3060 Lite Hash Rate angehalten: ist abgestürzt (Signal 11)."
clean

echo "== an exit status at start, and a result that is neither"
check "exit 1 at 0.4 s: exit 0" "$(died "$(U exits1 a2)")" 0
has "exit 1 at 0.4 s: said" "$T/err" "it exited with status 1."
check "exit 1 at 0.4 s: kept" "$(kept)" 1
clean
check "a timeout: exit 0" "$(died "$(U timeout a9)")" 0
has "a timeout: systemd's word" "$T/err" "systemd reports timeout."
clean

echo "== nothing to tell"
for c in "launcher a3:a launcher or a single-instance program that handed over and ended cleanly" "killed a4:a program the person or the system killed (SIGKILL)" "late a5:a crash an hour after the start" "unrouted a6:a program this page sent nowhere" "editor a7:another program with no GPU variable" "nodesktop a8:a service with no desktop entry" "longlived b1:a program that ended cleanly after ten minutes" "sparky-browser b4:a program closed with SIGTERM"; do
	u=${c%%:*}; why=${c#*:}
	check "$why: exit 0" "$(died "$(U $u)")" 0
	check "$why: nothing kept" "$(kept)" 0
	check "$why: nothing said" "$(wc -c <"$T/err" | tr -d ' ')" 0
done
check "a unit that is not an application: exit 0" "$(died sparky-stereo-gpu-died@x.service)" 0
check "a unit that is not an application: nothing kept" "$(kept)" 0
printf '[Launch]\nDiedWithin=0\n' >"$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"
check "the person turned the notice off: exit 0" "$(died "$(U exits1 a2)")" 0
check "the person turned the notice off: nothing kept" "$(kept)" 0
printf '[Launch]\nDiedWithin=2\n' >"$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"
check "a window of 2 seconds: a death at 3.2 s is late, nothing kept" "$(died "$(U sparky-browser a1)"; kept)" "0
0"
check "a window of 2 seconds: a death at 0.4 s is told" "$(died "$(U exits1 a2)"; kept)" "0
1"
rm -f "$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"
echo "== systemd cannot be asked: said, never silent"
check "a unit systemd does not have: exit 3" "$(died "$(U ghost ff)")" 3
has "a unit systemd does not have: said" "$T/err" "Could not ask systemd how app-ghost@ff.service ended"

echo "== the death ends when the program runs well"
died "$(U exits1 a2)" >/dev/null
check "kept before" "$(kept)" 1
check "a hand-over that ended cleanly after 0.2 s: exit 0" "$(survived "$(U exits1 b3)")" 0
check "a hand-over does not end it: still kept" "$(kept)" 1
check "the same program, ended cleanly after ten minutes: exit 0" "$(survived "$(U exits1 b2)")" 0
check "ended cleanly after ten minutes: the death is over" "$(kept)" 0
died "$(U exits1 a2)" >/dev/null
check "another program's clean end does not end it" "$(survived "$(U longlived b1)"; kept)" "0
1"
clean

echo "== Use NAME: the desktop's own key, for this program, and the death is over"
died "$(U sparky-browser a1)" >/dev/null
check "kept before" "$(kept)" 1
check "Use the desktop's GPU: exit 0" "$("$BIN/sparky-stereo-gpu-env" --use-app sparky-browser.desktop pci-0000:0b:00.0 >"$T/out" 2>"$T/err"; echo $?)" 0
check "it is KDE's own key in the person's copy of the entry" "$(grep -c '^PrefersNonDefaultGPU=false' "$XDG_DATA_HOME/applications/sparky-browser.desktop")" 1
check "the death is over" "$(kept)" 0
check "the program now starts on the desktop's GPU (no variables)" "$("$BIN/sparky-stereo-gpu-env" --app sparky-browser.desktop --profile performance | wc -l)" 0
rm -f "$XDG_DATA_HOME/applications/sparky-browser.desktop"
died "$(U sparky-browser a1)" >/dev/null
check "a GPU a desktop entry cannot name: exit 4" "$("$BIN/sparky-stereo-gpu-env" --use-app sparky-browser.desktop pci-0000:09:00.0 >"$T/out" 2>"$T/err"; echo $?)" 4
has "a GPU a desktop entry cannot name: said" "$T/err" "That GPU cannot be chosen for one program here."
check "a GPU a desktop entry cannot name: still kept" "$(kept)" 1
check "an entry that is not there: exit 2" "$("$BIN/sparky-stereo-gpu-env" --use-app nothing.desktop pci-0000:0b:00.0 >"$T/out" 2>"$T/err"; echo $?)" 2
check "no entry was written for it" "$(ls "$XDG_DATA_HOME/applications" | wc -l)" 0

echo "died: $pass passed, $fail failed"
[ "$fail" = 0 ]
