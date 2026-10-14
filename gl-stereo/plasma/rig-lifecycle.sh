# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced only by rig.sh, with its private buses and display.
capture() { timeout 10 "$repo/out/plasma/build/capture" "$run/$1.png" window >>"$run/capture.log" 2>&1; }
wait_frame() {
    local check=()
    if [[ ${RIG_REAL_LOCK:-0} == 1 ]]; then check+=(--prompt); fi
    for attempt in {1..20}; do
        if [[ ${RIG_REAL_LOCK:-0} == 1 ]]; then "$repo/out/plasma/build/rig-input"; fi
        capture "$1"
        if python3 plasma/check-eyes.py "$run/$1.png" "${check[@]}" >>"$run/resume-check.log" 2>&1; then return; fi
        sleep .5
    done
    return 1
}
locked() {
    dbus-send --session --print-reply --dest=org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive >"$run/locked-$1.log"
    grep -q "boolean $1" "$run/locked-$1.log"
}
if [[ ${RIG_REAL_LOCK:-0} == 1 ]]; then
    locked true
    "$repo/out/plasma/build/rig-input" 30
    "$repo/out/plasma/build/rig-input" 28
    sleep 2
    locked true
fi
dbus-send --system --print-reply --dest=org.freedesktop.UPower /org/freedesktop/UPower org.sparky.Test.SetBattery boolean:true >"$run/battery.log"
sleep 1
if [[ ${RIG_REAL_LOCK:-0} == 1 ]]; then capture battery; fi
dbus-send --system --print-reply --dest=org.freedesktop.UPower /org/freedesktop/UPower org.sparky.Test.SetBattery boolean:false >>"$run/battery.log"
sleep 2
wait_frame restored
kscreen-doctor --dpms off >"$run/dpms.log" 2>&1
sleep 1
kscreen-doctor --dpms on >>"$run/dpms.log" 2>&1
sleep 1
if [[ ${RIG_REAL_LOCK:-0} == 1 ]]; then "$repo/out/plasma/build/rig-input"; fi
sleep 2
wait_frame awake
if [[ ${RIG_REAL_LOCK:-0} == 1 ]]; then
    pkill -TERM -x starfield
    sleep 7
    capture producer-failed
    locked true
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1/session/auto org.sparky.Test.RequestUnlock >"$run/unlock.log"
    sleep 2
    locked false
    if pgrep -x kscreenlocker_g >/dev/null; then exit 1; fi
else
    "$repo/out/plasma/build/rig-input"
    sleep 1
    grep -q 'running false greeter false' "$run/show.log"
    timeout 10 "$repo/out/plasma/build/capture" "$run/dismissed.png" >>"$run/capture.log" 2>&1
fi
