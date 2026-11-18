#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As the person in a container with the package installed, a private Xvfb, no network: two launchers started at once (the tray's autostart and the menu entry) must give
# ONE signer that answers, and the second start must find it answering. Usage: twostarts.sh [LAUNCHER] [OUT]
LAUNCHER=${1:-/usr/bin/pjeoffice-pro}; OUT=${2:-/scratch/out}; mkdir -p "$OUT"
export DISPLAY=:97 LANG=C.UTF-8
Xvfb :97 -screen 0 1024x768x24 -nolisten tcp > "$OUT/xvfb.log" 2>&1 &
sleep 1
mkdir -p "$HOME/.pjeoffice-pro"
$LAUNCHER > "$OUT/start-1.txt" 2>&1 & P1=$!
$LAUNCHER > "$OUT/start-2.txt" 2>&1 & P2=$!
wait $P1; R1=$?; wait $P2; R2=$?
sleep 3
N=$(ps -u "$(id -u)" -o args= | grep -c "[P]jeOfficePROUser")
ANS=$(curl -fs --max-time 3 -X PUT -H 'Content-Type: application/json' -H 'Force-Preflight: true' -H 'Origin: http://127.0.0.1:8800' 'http://127.0.0.1:8800/pjeOffice/?u=18' | grep -c success)
echo "launcher exits $R1 and $R2, signer processes $N, answers $ANS"
grep -c "Tentativa de shutdown" "$HOME/.local/state/sparky-pjeoffice/signer.log" 2>/dev/null | sed 's/^/shutdown lines in the log: /'
for p in $(ps -u "$(id -u)" -o pid=,args= | grep "[P]jeOfficePROUser" | awk '{print $1}'); do kill "$p"; done
if [ "$R1" = 0 ] && [ "$R2" = 0 ] && [ "$N" = 1 ] && [ "$ANS" = 1 ]; then echo "RESULT: PASS (one signer)"; exit 0; fi
echo "FAIL  two starts gave $N signers"; echo "RESULT: FAIL"; exit 1
