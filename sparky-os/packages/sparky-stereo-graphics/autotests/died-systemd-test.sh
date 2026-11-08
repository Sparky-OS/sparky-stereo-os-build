#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ORDER 467 against a real systemd user manager (not part of ctest: it needs PID 1 systemd in a container, see the package
# README, "Dying at start"). Programs are started the way KIO starts them (systemdprocessrunner.cpp: a transient service
# app-NAME@ID.service, Type=simple, ExitType=cgroup, Slice=app.slice, SourcePath the desktop file, the environment the
# resolver printed), then die, hand over, or are closed. Run as the logged-in user with XDG_RUNTIME_DIR set, the package
# installed, and BIN the folder of makefixture. With the drop-in (share/systemd/user) removed every case that should be told fails.
set -u
BIN=${BIN:?}
WINDOW=${WINDOW:-10}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
T=$(mktemp -d)
trap 'systemctl --user stop "app-*" 2>/dev/null; systemctl --user unset-environment SPARKY_STEREO_GRAPHICS_ROOT SPARKY_STEREO_POWER_PROFILE XDG_DATA_DIRS; rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
"$BIN/makefixture" host "$T/host" || exit 1
mkdir -p "$T/usr/applications"
B=$T/usr/applications/sparky-browser.desktop
printf '[Desktop Entry]\nType=Application\nName=Sparky Browser\nExec=true\nCategories=Network;WebBrowser;\n' >"$B"
export SPARKY_STEREO_GRAPHICS_ROOT=$T/host SPARKY_STEREO_POWER_PROFILE=performance XDG_DATA_DIRS=$T/usr
systemctl --user set-environment SPARKY_STEREO_GRAPHICS_ROOT="$T/host" SPARKY_STEREO_POWER_PROFILE=performance XDG_DATA_DIRS="$T/usr"
ROUTE=$(sparky-stereo-gpu-env --app "$B" --profile performance)
[ -n "$ROUTE" ] || { echo "no route"; exit 1; }
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/sparky-stereo-problems
rec() { echo "$STATE/sparky-stereo-graphics_died-$1.json"; }
rm -f "$STATE"/sparky-stereo-graphics_died-*
systemctl --user reset-failed "app-*" 2>/dev/null
# kio NAME ID routed|plain COMMAND...: start it as KIO does
kio() {
	local name=$1 id=$2 routed=$3 args=() line
	shift 3
	if [ "$routed" = routed ]; then
		for line in $ROUTE; do args+=("--setenv=$line"); done
	fi
	systemd-run --user --quiet --no-block --unit="app-${name//-/\\x2d}@$id.service" --slice=app.slice -p Type=simple -p ExitType=cgroup \
		-p "SourcePath=$B" --description="Sparky Browser - Web Browser" "${args[@]}" -- "$@"
}
waitrec() { local _; for _ in $(seq 1 "${2:-40}"); do [ -e "$(rec "$1")" ] && return 0; sleep 0.25; done; return 1; }
told() { waitrec "$1" 24; echo $?; }
silent() { sleep "${2:-4}"; test -e "$(rec "$1")"; echo $?; }
now_ms() { date +%s%3N; }

echo "== dies at start on its GPU"
t0=$(now_ms)
kio crash c1 routed sh -c 'sleep 1; kill -s SEGV $$$$'
check "a crash a second after the start on the routed GPU is kept" "$(told crash)" 0
echo "   told $(( $(now_ms) - t0 )) ms after the start (the program lived 1000 ms)"
check "its message names the program, the GPU and how" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["text_en"].split(" It was")[0])' "$(rec crash)")" "Sparky Browser stopped right after it started on NVIDIA GeForce RTX 3060 Lite Hash Rate: it crashed (signal 11)."
check "a quick exit status 3" "$(kio exit3 c2 routed sh -c 'echo the GPU said no >&2; exit 3'; told exit3)" 0
check "its last output is kept" "$(python3 -I -c 'import json,sys; print("the GPU said no" in json.load(open(sys.argv[1]))["output"])' "$(rec exit3)")" True
check "a program with a dash in its name is kept under that name (\\x2d read back)" "$(kio sparky-stereo-browser c3 routed sh -c 'exit 7'; told sparky-stereo-browser)" 0
rm -f "$STATE"/sparky-stereo-graphics_died-*
systemctl --user reset-failed "app-*" 2>/dev/null

echo "== not told"
kio launcher d1 routed sh -c '(sleep 30 >/dev/null 2>&1 &); exit 0'
check "a launcher that hands over (exit 0, the program still running)" "$(silent launcher 3)" 1
check "  the hand-over keeps the unit running while the program lives" "$(systemctl --user is-active app-launcher@d1.service)" active
systemctl --user stop app-launcher@d1.service
kio single d2 routed sh -c 'exit 0'
check "a single-instance program that hands over and exits 0" "$(silent single 3)" 1
kio closed d3 routed sleep 60
sleep 1
systemctl --user stop app-closed@d3.service
check "a program the person closes (SIGTERM from the manager)" "$(silent closed 3)" 1
kio termed d4 routed sh -c 'sleep 1; kill -s TERM $$$$'
check "a program that ends on SIGTERM" "$(silent termed 4)" 1
kio plaincrash d5 plain sh -c 'sleep 1; kill -s SEGV $$$$'
check "a crash of a program sent to no GPU" "$(silent plaincrash 5)" 1
kio late d6 routed sh -c "sleep $((WINDOW + 3)); kill -s SEGV \$\$\$\$"
check "a crash after the window ($WINDOW s)" "$(silent late $((WINDOW + 6)))" 1
kio longlived d7 routed sh -c "sleep 1; exit 0"
check "a program that ended cleanly" "$(silent longlived 3)" 1

echo "== the death ends when the program runs well"
kio ok e1 routed sh -c 'sleep 1; exit 9'
check "kept" "$(told ok)" 0
kio ok e2 routed sh -c 'sleep 1; exit 0'
check "a clean end after 1 s (a hand-over) does not end it" "$(silent ok 4)" 0
kio ok e3 routed sh -c "sleep $((WINDOW + 2)); exit 0"
sleep $((WINDOW + 5))
check "a clean end after $((WINDOW + 2)) s ends it" "$(test -e "$(rec ok)"; echo $?)" 1
echo "pass $pass fail $fail"
[ "$fail" = 0 ]
