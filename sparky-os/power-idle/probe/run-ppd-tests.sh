#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL2 License
# Last update 2026/10/08
set -euo pipefail
: "${POWER_IDLE_WORK:?Set POWER_IDLE_WORK to workspace scratch}"
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$POWER_IDLE_WORK/ppd-runtime/src" "$POWER_IDLE_WORK/ppd-evidence"
for package in "$POWER_IDLE_WORK"/ppd-debs/*.deb; do
	dpkg-deb -x "$package" "$POWER_IDLE_WORK/ppd-root"
done
install -m755 "$POWER_IDLE_WORK/ppd-root/usr/libexec/power-profiles-daemon" "$POWER_IDLE_WORK/ppd-runtime/src/power-profiles-daemon"
install -m755 "$POWER_IDLE_WORK/power-profiles-daemon-0.30/src/powerprofilesctl" "$POWER_IDLE_WORK/ppd-runtime/src/powerprofilesctl"
export LD_LIBRARY_PATH="$POWER_IDLE_WORK/ppd-root/usr/lib/x86_64-linux-gnu"
export GI_TYPELIB_PATH="$LD_LIBRARY_PATH/girepository-1.0"
export PYTHONPATH="$POWER_IDLE_WORK/ppd-root/usr/lib/python3/dist-packages:$POWER_IDLE_WORK/power-profiles-daemon-0.30/tests"
export LD_PRELOAD="$LD_LIBRARY_PATH/libumockdev-preload.so.0"
export PPD_LD_PRELOAD=
export top_builddir="$POWER_IDLE_WORK/ppd-runtime"
rm -f "$POWER_IDLE_WORK/ppd-evidence/result.txt"
/usr/bin/python3 "$POWER_IDLE_WORK/power-profiles-daemon-0.30/tests/integration_test.py" \
	Tests.test_amd_pstate Tests.test_amd_pstate_upower Tests.test_amdgpu_dpm \
	Tests.test_amdgpu_dpm_manual Tests.test_amdgpu_panel_power Tests.test_hold_release_profile \
	Tests.test_intel_pstate Tests.test_intel_pstate_upower Tests.test_amd_pstate_passive \
	>"$POWER_IDLE_WORK/ppd-evidence/upstream.log" 2>&1
if [[ -n ${POWER_IDLE_PROFILE_DEFAULTS:-} ]]; then
	/usr/bin/python3 "$HERE/profile-integration.py" EditionProfiles.test_modes \
		>"$POWER_IDLE_WORK/ppd-evidence/edition.log" 2>&1
fi
echo PASS >"$POWER_IDLE_WORK/ppd-evidence/result.txt"
