#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ORDER 70, the partners' card: --category partners, --print compute-env and --print memory, the processor as a choice,
# and a card no compute driver reaches said and kept, never replaced. Black box against the built commands, so the same
# checks run against an older build (red) and this one (green).
# BIN: folder with sparky-stereo-gpu-env and makefixture. SRC: the package source.
set -u
BIN=${BIN:?}
SRC=${SRC:?}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { # name got expected
	if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi
}
has() { # name file text
	if grep -qF -- "$3" "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: '$3' not in: $(head -c 600 "$2")"; fi
}
for m in one host; do "$BIN/makefixture" $m "$T/$m" || { echo "makefixture $m failed"; exit 1; }; done
export XDG_CONFIG_HOME=$T/config XDG_CONFIG_DIRS=$T/none XDG_DATA_HOME=$T/data XDG_DATA_DIRS=$T/usr XDG_STATE_HOME=$T/state
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$T/no-system-bus LANG=C.UTF-8 SPARKY_STEREO_POWER_PROFILE=balanced
unset LANGUAGE LC_ALL LC_MESSAGES WAYLAND_DISPLAY DISPLAY DRI_PRIME MESA_VK_DEVICE_SELECT VK_LOADER_DRIVERS_SELECT __NV_PRIME_RENDER_OFFLOAD
mkdir -p "$XDG_CONFIG_HOME" "$T/none"
CFG=$XDG_CONFIG_HOME/sparky-stereo-graphicsrc
PROBLEMS=$XDG_STATE_HOME/sparky-stereo-problems
rec() { echo "$PROBLEMS/sparky-stereo-graphics_$1.json"; }
sparky-stereo-problems catalog sparky-stereo-graphics "$SRC/po" "$T/catalog" --domain kcm_sparkystereo_graphics \
	--context "@info" --context "@item kind of program" --context "@action:button" \
	--subject "@title notification|A graphics choice cannot be used" >/dev/null || exit 1
export SPARKY_STEREO_PROBLEMS_CATALOG=$T/catalog:/usr/lib/systemd/catalog
save() { printf '%b' "$1" >"$CFG"; }
env_for() { SPARKY_STEREO_GRAPHICS_ROOT=$T/$1 "$BIN/sparky-stereo-gpu-env" "${@:2}"; }
rc_of() { "$@" >"$T/out" 2>"$T/err"; echo $?; }
lines() { tr '\n' ' ' <"$T/out"; }

echo "== Automatic: the card measured best (not measured here: the discrete card), only it visible to every runner"
check "Automatic: exit 0" "$(rc_of env_for host --category partners --print compute-env)" 0
check "Automatic: the RTX 3060 alone" "$(lines)" "CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=GPU-00000000-1111-2222-3333-444444444444 HIP_VISIBLE_DEVICES=-1 VK_LOADER_DRIVERS_SELECT=*nvidia* DRI_PRIME=pci-0000_01_00_0! "
check "Automatic: the reason" "$(env_for host --category partners --print reason)" unmeasured
check "Automatic: the card" "$(env_for host --category partners --print id)" pci-0000:01:00.0
check "Automatic: nothing kept" "$(test -e "$(rec partners)"; echo $?)" 1

echo "== the APU chosen: CUDA sees nothing, ROCm and Vulkan only the APU"
save '[Render]\nPartners=pci-0000:0b:00.0\n'
check "the APU: exit 0" "$(rc_of env_for host --category partners --print compute-env)" 0
check "the APU alone" "$(lines)" "CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=-1 ROCR_VISIBLE_DEVICES=0 HIP_VISIBLE_DEVICES=0 VK_LOADER_DRIVERS_SELECT=*radeon* DRI_PRIME=pci-0000_0b_00_0! "
check "the APU, as shell lines" "$(env_for host --category partners --print compute-env --shell | tail -1)" "export DRI_PRIME='pci-0000_0b_00_0!'"
check "the APU's own memory" "$(env_for host --category partners --print memory)" 536870912

echo "== Processor only"
save '[Render]\nPartners=cpu\n'
check "the processor: exit 0" "$(rc_of env_for host --category partners --print compute-env)" 0
check "the processor: every card hidden" "$(lines)" "CUDA_VISIBLE_DEVICES=-1 HIP_VISIBLE_DEVICES=-1 GGML_VK_VISIBLE_DEVICES= "
check "the processor: its id" "$(env_for host --category partners --print id)" cpu
check "the processor: its name" "$(env_for host --category partners --print gpu)" "Processor only"
check "the processor: no memory to give" "$(rc_of env_for host --category partners --print memory)" 1
check "--choice cpu with the compute variables" "$(env_for host --choice cpu --print compute-env | head -1)" "CUDA_VISIBLE_DEVICES=-1"
check "--choice cpu for drawing: not a choice" "$(rc_of env_for host --choice cpu)" 2
check "a computer with one card, the processor chosen: kept" "$(env_for one --category partners --print compute-env | wc -l)" 3

echo "== the choice from the command (\"Use NAME\" of a kept problem)"
save ''
check "--use partners cpu: exit 0" "$(rc_of env_for host --use partners cpu)" 0
check "--use partners cpu: written" "$(grep -c '^Partners=cpu$' "$CFG")" 1
check "--use games cpu: not a choice" "$(rc_of env_for host --use games cpu)" 2
check "--use games cpu: nothing written" "$(grep -c '^Games=' "$CFG")" 0

echo "== the card's memory"
check "list json: the APU's memory, NVIDIA's unknown in a fixture" "$(env_for host --list --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["memory"], d[1]["memory"])')" "536870912 0"

echo "== a card that is not here, or that no compute driver reaches: said, kept, never replaced"
save '[Render]\nPartners=pci-0000:42:00.0\n'
check "a card that is not here: exit 4" "$(rc_of env_for host --category partners --print compute-env)" 4
check "a card that is not here: no variables" "$(cat "$T/out")" ""
has "a card that is not here: said" "$T/err" "The GPU you chose for partners, at PCI address 0000:42:00.0, is not in this computer now."
has "a card that is not here: the processor offered" "$T/err" "cpu  Processor only"
check "a card that is not here: kept" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["data"]["kind"], d["data"]["requested"])' "$(rec partners)" 2>&1)" "gpu-missing pci-0000:42:00.0"
cp -a "$T/host" "$T/host-novk"
rm -rf "$T/host-novk/usr/share/vulkan/icd.d/radeon_icd.x86_64.json" "$T/host-novk/sys/class/kfd"
for l in "$T/host-novk"/sys/class/drm/card*/device "$T/host-novk"/sys/bus/pci/devices/*; do
	t=$(readlink "$l"); ln -sfn "$T/host-novk${t#"$T/host"}" "$l"
done
save '[Render]\nPartners=pci-0000:0b:00.0\n'
check "the APU with no compute driver: exit 4" "$(rc_of env_for host-novk --category partners --print compute-env)" 4
check "the APU with no compute driver: no variables" "$(cat "$T/out")" ""
has "the APU with no compute driver: said" "$T/err" "The card you chose for partners, AMD Radeon Vega Series / Radeon Vega Mobile Series, cannot run them: no installed driver reaches it for computing (no Vulkan driver for its driver, amdgpu, no CUDA, no ROCm)."
has "the APU with no compute driver: what to do" "$T/err" "Install a Vulkan driver for this card, or choose another card or Processor only for partners in System Settings, Graphics."
L=$(sparky-stereo-problems list --json sparky-stereo-graphics)
pick() { printf '%s' "$L" | python3 -I -c "import json,sys; p=[x for x in json.load(sys.stdin) if x['key'] == 'partners'][0]; print($1)" 2>&1; }
check "kept by the engine" "$(pick 'p["scope"]')" person
has "the engine says what failed" <(pick 'p["text"]') "cannot run them: no installed driver reaches it for computing"
check "the other card and the processor as actions, then the page" "$(pick '[a["id"] for a in p["actions"]]')" "['use:pci-0000:01:00.0', 'use:cpu', 'open']"
check "the processor's action" "$(pick 'p["labels"][[a["id"] for a in p["actions"]].index("use:cpu")]')" "Use the processor only"
check "the same in Portuguese" "$(LANG=pt_BR.UTF-8 sparky-stereo-problems list --json sparky-stereo-graphics | python3 -I -c "import json,sys; p=[x for x in json.load(sys.stdin) if x['key'] == 'partners'][0]; print(p['labels'][[a['id'] for a in p['actions']].index('use:cpu')])" 2>&1)" "Usar somente o processador"
save '[Render]\nPartners=pci-0000:01:00.0\n'
check "a card that works again: exit 0" "$(rc_of env_for host-novk --category partners --print compute-env)" 0
check "a card that works again: its record goes" "$(test -e "$(rec partners)"; echo $?)" 1

echo "== the wrapper: a program that computes starts with only its card, or not at all"
RUN=$SRC/share/sparky-stereo-gpu-run
wrapped() { (export PATH=$BIN:$PATH SPARKY_STEREO_GRAPHICS_ROOT=$T/host; sh "$RUN" "$@"); }
save ''
check "Automatic: the program gets only the RTX 3060" "$(wrapped --compute --category partners env | grep -E '^(CUDA_VISIBLE_DEVICES|HIP_VISIBLE_DEVICES|DRI_PRIME)=' | sort | tr '\n' ' ')" "CUDA_VISIBLE_DEVICES=GPU-00000000-1111-2222-3333-444444444444 DRI_PRIME=pci-0000_01_00_0! HIP_VISIBLE_DEVICES=-1 "
check "a drawing selection left in the environment is removed" "$(MESA_VK_DEVICE_SELECT=1002:1638 MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1 wrapped --compute --category partners env | grep -c '^MESA_VK_DEVICE_SELECT')" 0
check "a card the caller chose for computing is kept, the page not asked" "$(CUDA_VISIBLE_DEVICES=7 wrapped --compute --category partners env | grep -E '^(CUDA_VISIBLE_DEVICES|DRI_PRIME)=' | tr '\n' ' ')" "CUDA_VISIBLE_DEVICES=7 "
save '[Render]\nPartners=cpu\n'
check "the processor: the program sees no card" "$(wrapped --compute --category partners env | grep -E '^(CUDA_VISIBLE_DEVICES|HIP_VISIBLE_DEVICES|GGML_VK_VISIBLE_DEVICES)=' | sort | tr '\n' ' ')" "CUDA_VISIBLE_DEVICES=-1 GGML_VK_VISIBLE_DEVICES= HIP_VISIBLE_DEVICES=-1 "
save '[Render]\nPartners=pci-0000:42:00.0\n'
check "a card that is not here: the program does not start" "$(DISPLAY=:9 wrapped --compute --category partners printf ran 2>"$T/err"; echo " rc=$?")" " rc=4"
has "a card that is not here: said" "$T/err" "The GPU you chose for partners, at PCI address 0000:42:00.0, is not in this computer now."
has "a card that is not here: the program was not started" "$T/err" "The program was not started."
check "a card that is not here, in Portuguese" "$( (export LANG=pt_BR.UTF-8; wrapped --compute --category partners printf ran 2>&1 >/dev/null) | grep -c 'O programa não foi iniciado.')" 1

echo "compute: $pass passed, $fail failed"
[ "$fail" = 0 ]
