#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# The command against the stand-in of the program (tests/standin: the HyperX Cloud II Wireless dongle 03f0:018b) and against the real program on its own test device
# (tests/standin-full): what is shown, what is refused, what is kept. Run inside a container with the package installed, as an ordinary user, HOME writable.
# Usage: bash engine-proof.sh THIS_FOLDER
T=${1:-/t}; export QT_QPA_PLATFORM=offscreen HOME=${HOME:-/tmp/h} XDG_CONFIG_HOME=${HOME:-/tmp/h}/.config HS_STANDIN_DIR=/tmp/hs-standin-proof; mkdir -p "$XDG_CONFIG_HOME" "$HS_STANDIN_DIR"
rm -f "$XDG_CONFIG_HOME/sparky-stereo-headsetrc" "$HS_STANDIN_DIR"/*
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
H() { PATH="$T/$1:$PATH" sparky-stereo-headset "${@:2}" 2>&1 | grep -v -e "^Detected locale" -e "^Qt depends" -e "^If this causes" -e "^for more information"; }
echo "== the stand-in HyperX dongle (battery and inactive time only)"
out=$(H standin status); [[ $out == *"HyperX Cloud II Wireless (03f0:018b)"* && $out == *"Battery at 80%"* && $out == *InactiveTime* && $out != *Sidetone* && $out != *Lights* && $out != *Equalizer* ]] && ok "it lists battery and inactive time and nothing else" || bad "status: $out"
echo 1 >"$HS_STANDIN_DIR/present"; echo 0 >"$HS_STANDIN_DIR/present"; out=$(H standin status); rc=$?; [[ $out == "No headset that HeadsetControl knows is connected." ]] && ok "no headset: it says so plainly" || bad "none: $out"
echo 1 >"$HS_STANDIN_DIR/present"
echo 20 >"$HS_STANDIN_DIR/battery"; echo BATTERY_CHARGING >"$HS_STANDIN_DIR/status"; out=$(H standin status); [[ $out == *"Charging, 20%"* ]] && ok "charging is said" || bad "charging: $out"
echo BATTERY_UNAVAILABLE >"$HS_STANDIN_DIR/status"; out=$(H standin status); [[ $out == *"switched off or out of range"* ]] && ok "a headset that is off says its battery is not known" || bad "off: $out"
echo BATTERY_AVAILABLE >"$HS_STANDIN_DIR/status"; echo 80 >"$HS_STANDIN_DIR/battery"
printf '[Headset 03f0:018b]\nInactiveTime=30\nSidetone=64\n' >"$XDG_CONFIG_HOME/sparky-stereo-headsetrc"; : >"$HS_STANDIN_DIR/log"
out=$(H standin apply); rc=$?
grep -qx -- "-d 03f0:018b -i 30" "$HS_STANDIN_DIR/log" && ok "apply sent the saved inactive time to that headset: -d 03f0:018b -i 30" || bad "apply log: $(cat "$HS_STANDIN_DIR/log")"
! grep -q -- "-s " "$HS_STANDIN_DIR/log" && [[ $out == *"does not report this setting"* ]] && ok "a saved sidetone the headset cannot take is refused with the reason, never sent" || bad "sidetone: $out / $(cat "$HS_STANDIN_DIR/log")"
echo "== the real program on its test device (every capability)"
rm -f "$XDG_CONFIG_HOME/sparky-stereo-headsetrc"
out=$(H standin-full status --json); for k in Sidetone Lights VoicePrompts InactiveTime EqualizerPreset; do [[ $out == *"\"$k\""* ]] || bad "full page lacks $k"; done
python3 - "$out" <<'P' && ok "the equalizer presets come in the program's own order (flat, bass boost, treble boost, v-shape)" || bad "preset order"
import json, sys
d = json.loads(sys.argv[1]); s = [x for x in d["headsets"][0]["settings"] if x["key"] == "EqualizerPreset"][0]
assert s["choices"] == ["flat", "bass boost", "treble boost", "v-shape"], s["choices"]
P
exit $failed
