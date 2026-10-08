#!/bin/bash
set -euo pipefail
[[ -e /.dockerenv ]]
sdk=$PWD/work/sdk-extra
export CMAKE_PREFIX_PATH=$sdk/usr LD_LIBRARY_PATH=$PWD/work/power-package-payload/usr/lib/x86_64-linux-gnu:$sdk/usr/lib/x86_64-linux-gnu
c++ -std=c++20 powerdevil/autotests/migrateconfig/migrateconfig.cpp -o work/legacy-migrator $(pkg-config --cflags --libs Qt6Widgets Qt6Core Qt6DBus) -I/usr/include/KF6/KConfigCore -I/usr/include/KF6/KConfig -lKF6ConfigCore -Iwork/power-source-check/daemon -Iwork/packaged-timeline/timeline-build -Lwork/power-package-payload/usr/lib/x86_64-linux-gnu -Wl,-rpath-link=$sdk/usr/lib/x86_64-linux-gnu -lpowerdevilcore
cmake --build work/packaged-timeline/timeline-build --target settings-probe -j4
export QT_QPA_PLATFORM=offscreen XDG_CONFIG_DIRS=$PWD/work/defaults-payload/etc/xdg
root=$PWD/work/legacy-migration
mkdir -p "$root"
dbus-daemon --session --fork --print-address --print-pid >"$root/bus"
export DBUS_SYSTEM_BUS_ADDRESS=$(head -n 1 "$root/bus")
bus_pid=$(tail -n 1 "$root/bus"); hardware_pid=
trap 'kill "${hardware_pid:-}" "$bus_pid" 2>/dev/null || true; wait "${hardware_pid:-}" 2>/dev/null || true' EXIT
for model in desktop laptop; do
 extra=(); [[ $model == laptop ]] && extra=(--laptop --supply)
 work/packaged-timeline/timeline-build/timeline-hardware "${extra[@]}" >"$root/$model-upower.log" 2>&1 &
 hardware_pid=$!
 for attempt in {1..100}; do grep -q READY "$root/$model-upower.log" && break; sleep .02; done
 grep -q READY "$root/$model-upower.log"
 export HOME=$root/$model-home
 mkdir -p "$HOME/.qttest/config"
 work/legacy-migrator --src-profilesrc powerdevil/autotests/migrateconfig/test1_initial_powermanagementprofilesrc --dest-powerdevilrc "$root/$model-powerdevilrc" --dest-profilesrc "$root/$model-profilesrc"
 export XDG_CONFIG_HOME=$root/$model-config
 mkdir -p "$XDG_CONFIG_HOME"
 cp "$root/$model-powerdevilrc" "$XDG_CONFIG_HOME/powerdevilrc"
 work/packaged-timeline/timeline-build/settings-probe --legacy >"$root/$model-settings.log" 2>&1
 kill "$hardware_pid"; wait "$hardware_pid" || true; hardware_pid=
done
printf 'PASS legacy default sleep, timeouts, buttons and lid choices survive new packaged system defaults on desktop and laptop\n' >work/legacy-migration.result
