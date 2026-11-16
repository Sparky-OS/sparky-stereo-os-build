#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ulimit -c 0
case_name=${1:?published, candidate or installed}
scale=${2:-1}
phase=${3:-page}
result=/lane/evidence/${case_name}-${scale}
if [[ $phase != page ]]; then result=/lane/evidence/${phase}-${case_name}-${scale}; fi
mkdir -p "$result"
session_home=$(mktemp -d /work/pa19-home-${phase}-${case_name}-${scale}-XXXXXX)
export HOME=$session_home
export XDG_RUNTIME_DIR=$HOME/run
export XDG_CONFIG_HOME=$HOME/config
export XDG_CACHE_HOME=$HOME/cache
export XDG_DATA_HOME=$HOME/data
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
chmod 700 "$XDG_RUNTIME_DIR"
export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR PULSE_RUNTIME_PATH=$XDG_RUNTIME_DIR/pulse
export DISPLAY=:19 QT_QPA_PLATFORM=xcb QT_SCALE_FACTOR=$scale
export QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
export QT_ACCESSIBILITY=1
export LC_ALL=C.UTF-8
if [[ $phase == hotplug ]]; then
    mkdir -p "$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d" "$XDG_DATA_HOME/wireplumber/scripts"
    cp /lane/src/sparky-stereo-os-build/sparky-os/packages/sparky-stereo-hardware/share/wireplumber/50-sparky-stereo-new-output.conf "$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d/"
    cp /lane/src/sparky-stereo-os-build/sparky-os/packages/sparky-stereo-hardware/share/wireplumber/sparky-stereo-new-output.lua "$XDG_DATA_HOME/wireplumber/scripts/"
fi
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true; wait || true' EXIT
Xvfb :19 -screen 0 1600x1800x24 -nolisten tcp >"$result/xvfb.log" 2>&1 & pids+=($!)
pipewire >"$result/pipewire.log" 2>&1 & pids+=($!)
for n in {1..100}; do test -S "$XDG_RUNTIME_DIR/pipewire-0" && break; sleep .1; done
wireplumber >"$result/wireplumber.log" 2>&1 & pids+=($!)
pipewire-pulse >"$result/pulse.log" 2>&1 & pids+=($!)
for n in {1..100}; do pactl info >/dev/null 2>&1 && break; sleep .1; done
for name in out-a out-b; do
    pactl load-module module-null-sink sink_name="$name" sink_properties="device.description=$name" >>"$result/modules.txt"
done
for name in mic-a mic-b; do
    pw-cli create-node adapter "{ factory.name=support.null-audio-sink node.name=$name node.description=$name media.class=Audio/Source object.linger=true audio.position=[ FL FR ] }"
done
sleep 2
pactl load-module module-loopback source=mic-a sink=out-a \
    source_output_properties='media.name=pa19-module-capture' \
    sink_input_properties='media.name=pa19-module-playback' >>"$result/modules.txt"
# A client-backed control matching the bridge's workaround.
pw-loopback --name=pa19-bridge --capture-props='node.virtual=false target.object=mic-b node.dont-fallback=true media.name=pa19-bridge-capture' \
    --playback-props='node.virtual=false target.object=out-b node.dont-fallback=true media.name=pa19-bridge-playback' \
    >"$result/bridge.log" 2>&1 & pids+=($!)
# Real filter-chain module, hosted in its own client process.
pipewire -c /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-filter.conf >"$result/filter.log" 2>&1 & pids+=($!)
sleep 3
pactl -f json list sink-inputs >"$result/sink-inputs.json"
pactl -f json list source-outputs >"$result/source-outputs.json"
pw-dump >"$result/pw-dump.json"
if [[ $case_name == candidate ]]; then
    export QT_PLUGIN_PATH=/opt/order19/lib/x86_64-linux-gnu/plugins
    export QML_IMPORT_PATH=/opt/order19/lib/x86_64-linux-gnu/qml
    export LD_LIBRARY_PATH=/opt/order19/lib/x86_64-linux-gnu
    export XDG_DATA_DIRS=/opt/order19/share:/usr/share
fi
if [[ $phase == hotplug ]]; then
    python3 /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-hotplug.py "$result"
else
    gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus --method org.a11y.Bus.GetAddress >"$result/a11y.txt"
    ui_mode=$case_name
    if [[ $case_name == installed ]]; then ui_mode=candidate; fi
    if [[ $phase == applet ]]; then
        python3 /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-applet.py "$result" "$ui_mode"
    else
        kcmshell6 kcm_pulseaudio >"$result/kcm.log" 2>&1 & pids+=($!)
        sleep 5
        python3 /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-ui.py "$result" "$ui_mode"
    fi
fi
