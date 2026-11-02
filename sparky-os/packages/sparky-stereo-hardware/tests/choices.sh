#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/01
# The NVIDIA choice of the installed tool, in a container, with a fixture and --dry-run only (nothing is installed): the
# edition's driver is the default, nouveau is chosen only by --nvidia nouveau, an unknown choice is refused, and a dry run
# whose apt does not know the edition's module says what would stop the setup instead of ending without a word.
# Run after the package's files are in place (container-final.sh, or payload.sh laid into /).
set -euo pipefail
[[ -e /.dockerenv ]] || exit 1
FIXTURE=$(cd "$(dirname "$0")" && pwd)/fixtures/creative-nvidia-laptop
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
run_tool() { sparky-stereo-hardware --auto --dry-run --fixture "$FIXTURE" "$@"; }
run_tool >"$T/default"
grep -Fxq $'action\tnvidia-open' "$T/default"
grep -q 'Would install sparky-stereo-nvidia-driver-lock and sparky-stereo-cuda-repo' "$T/default" || grep -q 'Would stop with an ERROR: apt finds no nvidia-kernel-open-dkms-stereo3d' "$T/default"
if grep -q 'Would keep nouveau' "$T/default"; then echo 'FAIL nouveau taken without the person choosing it'; exit 1; fi
echo 'PASS the default is the edition'"'"'s NVIDIA driver; nouveau is not taken for the person'
run_tool --nvidia nouveau >"$T/nouveau"
grep -q "Would keep nouveau for the NVIDIA graphics, as chosen (--nvidia nouveau)" "$T/nouveau"
if grep -q 'Would install sparky-stereo-nvidia-driver-lock' "$T/nouveau"; then echo 'FAIL the NVIDIA driver planned against the person'"'"'s choice'; exit 1; fi
echo 'PASS --nvidia nouveau keeps nouveau and plans nothing of NVIDIA'"'"'s'
if run_tool --nvidia proprietary >"$T/bad" 2>&1; then echo 'FAIL an unknown NVIDIA choice accepted'; exit 1; fi
[[ $(run_tool --nvidia proprietary >/dev/null 2>&1; echo $?) == 2 ]]
grep -q 'The NVIDIA choice is edition' "$T/bad"
echo 'PASS an unknown NVIDIA choice is refused (exit 2) with the two choices named'
if apt-cache show --no-all-versions nvidia-kernel-open-dkms-stereo3d >/dev/null 2>&1; then
	echo 'PASS (the edition'"'"'s module is known to apt here; the unknown-module dry run is not exercised)'
else
	grep -q 'Would stop with an ERROR: apt finds no nvidia-kernel-open-dkms-stereo3d' "$T/default"
	echo 'PASS a dry run whose apt does not know the module says what would stop the setup, and ends with status 0'
fi
# a command that fails without its own check stops the setup with where and what (the ERR trap), never a silent exit
if sparky-stereo-hardware --auto --dry-run --fixture /etc/hostname >"$T/stopped" 2>&1; then echo 'FAIL a broken fixture ran through'; exit 1; fi
grep -Eq '^ERROR Hardware Setup stopped at line [0-9]+, where this command failed: python3 .*detect.py' "$T/stopped" || { cat "$T/stopped"; exit 1; }
grep -q '^Hardware Setup finished with errors' "$T/stopped"
echo 'PASS a command failing without its own check stops the setup and says where and what failed'
