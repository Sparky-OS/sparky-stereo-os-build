#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# usage: run.sh GAMEMODE_SRC_DIR [ITERATIONS]  - run in a container with Qt 6 and KDE build tools and dbus.
# Builds the test against GAMEMODE_SRC_DIR (the src/ folder of the source), starts a private session bus with the
# stand-in service, runs the test ITERATIONS times (default 1), counts crashes (signals) and other failures.
# Exit 0 only when every run ended 0.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "${1:?src folder}" && pwd)
N=${2:-1}
B=${BUILD_DIR:-$(mktemp -d)}
cmake -S "$HERE" -B "$B" -G Ninja -DGAMEMODE_SRC="$SRC" >"$B/cmake.log" 2>&1 && cmake --build "$B" >"$B/build.log" 2>&1 || { tail -20 "$B/cmake.log" "$B/build.log"; exit 125; }
export B HERE N DELAY_MS=${DELAY_MS:-0}
ulimit -c 1
exec dbus-run-session -- bash -c '
python3 "$HERE/standin.py" >"$B/standin.log" 2>&1 & S=$!
for i in $(seq 100); do grep -q ready "$B/standin.log" && break; sleep 0.1; done
ok=0; crash=0; other=0
for i in $(seq "$N"); do
  "$B/race-test" >"$B/run.log" 2>&1; rc=$?
  if [ $rc = 0 ]; then ok=$((ok+1)); elif [ $rc -ge 128 ]; then crash=$((crash+1)); [ $crash = 1 ] && cp "$B/run.log" "$B/first-crash.log" && echo "first crash: signal $((rc-128)) at run $i"; else other=$((other+1)); [ $other = 1 ] && cp "$B/run.log" "$B/first-other.log"; fi
done
kill $S
echo "runs=$N ok=$ok crashed=$crash other_failures=$other"
[ $ok = "$N" ]'
