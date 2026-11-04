#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# Usage: test-installed.sh SOURCE EVIDENCE baseline|candidate (disposable root container, builder user).
# Installed binaries only. SOURCE supplies dpkg's functional fixtures, not executables.
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 0
SOURCE=${1:?source tree}
E=${2:?evidence directory}
MODE=${3:?baseline or candidate}
mkdir -p "$E"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
unset DPKG_BUILDTREE DPKG_DATADIR
export DPKG_STEREO_DISABLE=1 DPKG_STEREO_NO_PROJECT=1
dpkg-query -W -f='${Package}\t${Version}\t${Provides}\n' dpkg dpkg-dev libdpkg-perl >"$E/versions.txt"
dpkg --version >"$E/dpkg-version.txt"
sha256sum /usr/bin/dpkg /usr/bin/dpkg-maintscript-helper >"$E/installed-binaries.sha256"
case "$MODE" in
baseline)
    test "$(dpkg-query -W -f='${Version}' dpkg)" = 1.23.11+stereo3d2+lc1
    set +e
    runuser -u builder -- env -C "$SOURCE/tests/t-conffile-leancode" eatmydata make test >"$E/conffiles.log" 2>&1
    status=$?
    set -e
    printf '%s\n' "$status" >"$E/conffiles.exit"
    test "$status" = 2
    python3 - "$E/conffiles.log" <<'PYRED'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text()
expected = {'test_force_confask_unmodified', 'test_maintscript_move', 'test_maintscript_remove',
            'test_remove_on_upgrade_unmodified', 'test_split_unpack_configure', 'test_unmodified_upgrade'}
assert set(re.findall(r'^FAIL: (\w+)', text, re.M)) == expected, text[-3000:]
assert 'FAILED (failures=6, skipped=1)' in text, text[-3000:]
PYRED
    # Existing dpkg already preserves a real edit: this safety control must pass on both versions.
    set +e
    runuser -u builder -- env -C "$SOURCE/tests/t-conffile-leancode" python3 test.py ConffileTest.test_forged_projection_cannot_hide_edit >"$E/forgery.log" 2>&1
    status=$?
    set -e
    printf '%s\n' "$status" >"$E/forgery.exit"
    test "$status" = 0
    ;;
candidate)
    test "$(dpkg-query -W -f='${Version}' dpkg)" = 1.23.11+stereo3d3+lc1
    test "$(dpkg-query -W -f='${Provides}' dpkg)" = 'dpkg-lean-code (= 2)'
    set +e
    runuser -u builder -- env -C "$SOURCE/tests" eatmydata make installtest >"$E/functional.log" 2>&1
    status=$?
    set -e
    printf '%s\n' "$status" >"$E/functional.exit"
    test "$status" = 0
    set +e
    env -C "$SOURCE/tests/t-conffile-leancode" eatmydata make test >"$E/conffiles-root.log" 2>&1
    status=$?
    set -e
    printf '%s\n' "$status" >"$E/conffiles-root.exit"
    test "$status" = 0
    ;;
*) exit 2 ;;
esac
