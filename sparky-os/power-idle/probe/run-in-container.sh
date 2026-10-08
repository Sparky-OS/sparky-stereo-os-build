#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL2 License
# Last update 2026/10/08
set -euo pipefail

: "${POWERDEVIL_SOURCE:?Set POWERDEVIL_SOURCE to the inspected read-only source tree}"
: "${PLASMA_WORKSPACE_SOURCE:?Set PLASMA_WORKSPACE_SOURCE to the inspected read-only source tree}"
: "${POWER_IDLE_WORK:?Set POWER_IDLE_WORK to scratch inside this workspace}"
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$POWER_IDLE_WORK/evidence" "$POWER_IDLE_WORK/config-home" "$POWER_IDLE_WORK/user-config-home" "$POWER_IDLE_WORK/no-defaults"
EVIDENCE=$POWER_IDLE_WORK/evidence

dpkg-query -W qt6-base-dev libkf6config-dev extra-cmake-modules >"$EVIDENCE/toolchain.txt"
sha256sum "$POWERDEVIL_SOURCE/PowerDevilProfileSettings.kcfg" \
	"$POWERDEVIL_SOURCE/PowerDevilProfileSettings.kcfgc" \
	"$POWERDEVIL_SOURCE/daemon/powerdevilsettingsdefaults.cpp" \
	"$POWERDEVIL_SOURCE/daemon/powerdevilsettingsdefaults.h" \
	"$POWERDEVIL_SOURCE/daemon/powerdevilenums.h" \
	"$PLASMA_WORKSPACE_SOURCE/components/sessionsprivate/kscreenlockersettings.kcfg" \
	"$PLASMA_WORKSPACE_SOURCE/components/sessionsprivate/kscreensaversettings.kcfgc" >"$EVIDENCE/source-sha256.txt"
cmake -S "$HERE" -B "$POWER_IDLE_WORK/build" -DPOWERDEVIL_SOURCE="$POWERDEVIL_SOURCE" \
	-DPLASMA_WORKSPACE_SOURCE="$PLASMA_WORKSPACE_SOURCE" >"$EVIDENCE/configure.log" 2>&1
cmake --build "$POWER_IDLE_WORK/build" -j4 >"$EVIDENCE/build.log" 2>&1

export XDG_CONFIG_HOME=$POWER_IDLE_WORK/config-home
export QT_QPA_PLATFORM=offscreen
XDG_CONFIG_DIRS="$POWER_IDLE_WORK/no-defaults" "$POWER_IDLE_WORK/build/settings-probe" >"$EVIDENCE/stock-settings.log" 2>&1
XDG_CONFIG_DIRS="$HERE/../candidate-defaults" "$POWER_IDLE_WORK/build/settings-probe" --candidate >"$EVIDENCE/candidate-settings.log" 2>&1
cat >"$POWER_IDLE_WORK/user-config-home/powerdevilrc" <<'EOF'
[AC][Display]
DimDisplayIdleTimeoutSec=901
[AC][SuspendAndShutdown]
PowerButtonAction=16
EOF
XDG_CONFIG_HOME="$POWER_IDLE_WORK/user-config-home" XDG_CONFIG_DIRS="$HERE/../candidate-defaults" \
	"$POWER_IDLE_WORK/build/settings-probe" --candidate --user-override >"$EVIDENCE/user-override-settings.log" 2>&1

set +e
XDG_CONFIG_DIRS="$HERE/../candidate-defaults" "$POWER_IDLE_WORK/build/settings-probe" --candidate --require-timeline >"$EVIDENCE/blocked-timeline.log" 2>&1
TIMELINE_STATUS=$?
set -e
if [ "$TIMELINE_STATUS" -ne 1 ]; then
	echo "Expected the AC timeline check to fail with status 1; got $TIMELINE_STATUS" >"$EVIDENCE/result.txt"
	exit 1
fi
sha256sum --check "$EVIDENCE/source-sha256.txt" >"$EVIDENCE/source-stability.log"
echo 'PASS: stock settings, candidate settings, user overrides, and expected AC timeline failure (exit 1)' >"$EVIDENCE/result.txt"
