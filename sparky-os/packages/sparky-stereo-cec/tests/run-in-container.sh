#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/08
set -euo pipefail
ulimit -c 0
[[ -e /.dockerenv ]]
: "${CEC_WORK:?Set CEC_WORK to workspace scratch}"
: "${CEC_SDK:?Set CEC_SDK to extracted dependency prefix}"
rm -f "$CEC_WORK/cec-tests.result"
export XDG_RUNTIME_DIR="$CEC_WORK/cec-runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export CEC_TEST_ROOT="$CEC_WORK/cec-test-root"
export CEC_TEST_DEVICES="$CEC_TEST_ROOT/devices"
export CEC_TEST_STATE="$CEC_WORK/cec-state"
export CEC_TEST_FRAMES="$CEC_WORK/cec-frames"
export CEC_TEST_CONTROL="$CEC_WORK/cec-control"
export CEC_TEST_COMMAND=${CEC_TEST_COMMAND:-"$CEC_SDK/usr/bin/cec-ctl"}
export LD_LIBRARY_PATH="$CEC_SDK/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WAYLAND_DISPLAY=cec-test
export QT_QPA_PLATFORM=wayland
export QT_QUICK_BACKEND=software
dbus-daemon --session --fork --print-address --print-pid >"$CEC_WORK/cec-bus"
export DBUS_SYSTEM_BUS_ADDRESS=$(head -n 1 "$CEC_WORK/cec-bus")
bus_pid=$(tail -n 1 "$CEC_WORK/cec-bus")
"$CEC_WORK/cec-build/tests/cec-test-server" "$CEC_TEST_CONTROL" >"$CEC_WORK/cec-server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" "$bus_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; rm -f "$CEC_TEST_CONTROL"' EXIT
for attempt in {1..150}; do
	if [[ -p $CEC_TEST_CONTROL && -S $XDG_RUNTIME_DIR/cec-test ]]; then break; fi
	sleep 0.02
done
[[ -p $CEC_TEST_CONTROL && -S $XDG_RUNTIME_DIR/cec-test ]]
export LD_PRELOAD="$CEC_WORK/cec-build/tests/libcec-test-ioctl.so"
"$CEC_WORK/cec-build/tests/cec-test" >"$CEC_WORK/cec-tests.log" 2>&1
printf 'PASS native DPMS and real cec-ctl with synthetic adapter ioctls\n' >"$CEC_WORK/cec-tests.result"
