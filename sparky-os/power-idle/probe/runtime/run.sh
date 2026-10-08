#!/bin/bash
set -euo pipefail
[[ -e /.dockerenv ]]
sdk=${HEADLESS_SDK:-$PWD/work/sdk-extra}
HERE=$(cd "$(dirname "$0")" && pwd)
export LD_LIBRARY_PATH=$sdk/usr/lib/x86_64-linux-gnu:$sdk/usr/lib/x86_64-linux-gnu/weston
export QT_PLUGIN_PATH=$sdk/usr/lib/x86_64-linux-gnu/qt6/plugins QML_IMPORT_PATH=$sdk/usr/lib/x86_64-linux-gnu/qt6/qml
export XDG_DATA_DIRS=$sdk/usr/share:/usr/share PYTHONPATH=$sdk/usr/lib/python3/dist-packages
export XDG_CONFIG_DIRS=${TIMELINE_DEFAULTS:-$PWD/work/defaults-payload/etc/xdg}
export QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe KWIN_COMPOSE=Q
export TIMELINE_CASE=${TIMELINE_CASE:-battery}
export TIMELINE_RUN=${TIMELINE_RUN:-$PWD/work/runtime-$TIMELINE_CASE}
export HOME=$TIMELINE_RUN/home XDG_CONFIG_HOME=$TIMELINE_RUN/config XDG_RUNTIME_DIR=$TIMELINE_RUN/child
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$TIMELINE_RUN/parent" "$TIMELINE_RUN/tmp"
chmod 700 "$XDG_RUNTIME_DIR" "$TIMELINE_RUN/parent"
export TMPDIR=$TIMELINE_RUN/tmp
dbus-daemon --session --fork --print-address --print-pid >"$TIMELINE_RUN/session-bus"
dbus-daemon --session --fork --print-address --print-pid >"$TIMELINE_RUN/system-bus"
export DBUS_SESSION_BUS_ADDRESS=$(head -n 1 "$TIMELINE_RUN/session-bus") DBUS_SYSTEM_BUS_ADDRESS=$(head -n 1 "$TIMELINE_RUN/system-bus")
session_pid=$(tail -n 1 "$TIMELINE_RUN/session-bus"); system_pid=$(tail -n 1 "$TIMELINE_RUN/system-bus")
pids=()
cleanup() {
 for pid in "${pids[@]}" "$session_pid" "$system_pid"; do kill "$pid" 2>/dev/null || true; done
 sleep 0.2
 for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
python3 "$HERE/services.py" >"$TIMELINE_RUN/services.log" 2>&1 &
pids+=($!)
for attempt in {1..200}; do
 if grep -q READY "$TIMELINE_RUN/services.log"; then break; fi
 sleep 0.05
done
grep -q READY "$TIMELINE_RUN/services.log"
export WESTON_MODULE_MAP="headless-backend.so=$sdk/usr/lib/x86_64-linux-gnu/libweston-16/headless-backend.so;pixman-renderer.so=$sdk/usr/lib/x86_64-linux-gnu/libweston-16/pixman-renderer.so;kiosk-shell.so=$sdk/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
XDG_RUNTIME_DIR=$TIMELINE_RUN/parent "$sdk/usr/bin/weston" --backend=headless --renderer=pixman --fake-seat --socket=timeline-parent --width=640 --height=480 --idle-time=0 --shell=kiosk >"$TIMELINE_RUN/weston.log" 2>&1 &
pids+=($!)
for attempt in {1..200}; do
 if [[ -S $TIMELINE_RUN/parent/timeline-parent ]]; then break; fi
 sleep 0.05
done
[[ -S $TIMELINE_RUN/parent/timeline-parent ]]
env LD_PRELOAD="$sdk/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1" FAKETIME="@2026-10-08 15:00:00 x60" "$sdk/usr/bin/kwin_wayland" --wayland-display="$TIMELINE_RUN/parent/timeline-parent" --socket=timeline-kwin --width=640 --height=480 --no-global-shortcuts >"$TIMELINE_RUN/kwin.log" 2>&1 &
pids+=($!)
python3 - <<'PY'
import dbus,time
bus=dbus.SessionBus()
for attempt in range(600):
 if bus.name_has_owner('org.kde.KWin'): break
 time.sleep(0.05)
assert bus.name_has_owner('org.kde.KWin'), 'KWin workspace not ready'
print('READY KWin')
PY
export WAYLAND_DISPLAY=timeline-kwin QT_QPA_PLATFORM=wayland
"${TIMELINE_OBSERVER:-$PWD/work/timeline-observer}" >"$TIMELINE_RUN/dpms.log" 2>&1 &
pids+=($!)
powerprefix=${POWERDEVIL_PREFIX:-$PWD/work/power-package-payload/usr}
powerlib=$powerprefix/lib/x86_64-linux-gnu
export XDG_DATA_DIRS=$powerprefix/share:$XDG_DATA_DIRS
export SOLID_FAKEHW=$TIMELINE_RUN/hardware.xml
python3 - <<'PY'
import os
from pathlib import Path
case=os.environ['TIMELINE_CASE']
xml=Path('edition/sparky-os/power-idle/probe/hardware/'+('desktop' if case=='desktop' else 'laptop')+'.xml').read_text()
if case!='desktop': xml=xml.replace('<property key="isPowerSupply">true</property>', '<property key="isPowerSupply">true</property><property key="lastFullLevel">100</property><property key="currentLevel">'+('8' if case=='eco' else '70')+'</property><property key="chargeState">discharging</property>')
Path(os.environ['SOLID_FAKEHW']).write_text(xml)
PY
env LD_PRELOAD="$sdk/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1" FAKETIME="@2026-10-08 15:00:00 x60" LD_LIBRARY_PATH="$powerlib:$LD_LIBRARY_PATH" QT_PLUGIN_PATH="$powerlib/qt6/plugins:$QT_PLUGIN_PATH" QT_LOGGING_RULES="org.kde.powerdevil*=true;kf.idletime*=true" "$powerlib/libexec/org_kde_powerdevil" >"$TIMELINE_RUN/powerdevil.log" 2>&1 &
pids+=($!)
python3 - <<'PY'
import dbus,os,time
from pathlib import Path
bus=dbus.SessionBus()
for attempt in range(300):
 if bus.name_has_owner('org.kde.Solid.PowerManagement'): break
 time.sleep(.05)
assert bus.name_has_owner('org.kde.Solid.PowerManagement'), 'PowerDevil not ready'
obj=bus.get_object('org.kde.Solid.PowerManagement','/org/kde/Solid/PowerManagement')
expected={'desktop':'AC','laptop':'AC','battery':'Battery','eco':'LowBattery'}[os.environ['TIMELINE_CASE']]
assert obj.currentProfile(dbus_interface='org.kde.Solid.PowerManagement')==expected
Path(os.environ['TIMELINE_RUN']+'/ready-real-time').write_text(str(time.time()))
print('READY PowerDevil '+expected)
PY
sleep ${TIMELINE_DURATION:-38}
cat "$TIMELINE_RUN/dpms.log"
cat "$TIMELINE_RUN/logind.log"
