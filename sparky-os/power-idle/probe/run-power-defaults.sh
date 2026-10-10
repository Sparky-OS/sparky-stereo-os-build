#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
set -euo pipefail
[[ -e /.dockerenv && $EUID != 0 ]]
: "${POWER_DEFAULTS_NATIVE_ROOT:?Set to extracted Debian tools}"
: "${POWER_DEFAULTS_WORK:?Set to a fresh workspace scratch directory}"
: "${POWER_DEFAULTS_OUT:?Set to the workspace pending-pack directory}"
: "${KERNEL_SETTINGS_DEB:?Set to the repository kernel-settings package}"
HERE=$(cd "$(dirname "$0")" && pwd)
NATIVE=$(realpath "$POWER_DEFAULTS_NATIVE_ROOT")
WORK=$(realpath -m "$POWER_DEFAULTS_WORK")
mkdir "$WORK"
mkdir -p "$WORK/home" "$WORK/tmp"
export HOME=$WORK/home TMPDIR=$WORK/tmp PYTHONDONTWRITEBYTECODE=1
export LD_LIBRARY_PATH=$NATIVE/usr/lib/x86_64-linux-gnu:$NATIVE/usr/lib/x86_64-linux-gnu/systemd
export PYTHONPATH=$NATIVE/usr/lib/python3/dist-packages
OUT=$POWER_DEFAULTS_OUT bash "$HERE/../../packages/sparky-stereo-game-performance/build.sh"
HELPER_DEB=$POWER_DEFAULTS_OUT/sparky-stereo-game-performance_0.1.0_all.deb
dpkg-deb -x "$HELPER_DEB" "$WORK/helper"
dpkg-deb -e "$HELPER_DEB" "$WORK/helper/DEBIAN"
dpkg-deb -x "$KERNEL_SETTINGS_DEB" "$WORK/kernel"
dpkg-deb -e "$KERNEL_SETTINGS_DEB" "$WORK/kernel/DEBIAN"
(cd "$WORK/helper" && md5sum -c DEBIAN/md5sums)
(cd "$WORK/kernel" && md5sum -c DEBIAN/md5sums)
python3 "$HERE/power-defaults.py" "$WORK/kernel" "$NATIVE" "$WORK/defaults"
"$NATIVE/usr/bin/udevadm" verify "$WORK/kernel/usr/lib/udev/rules.d/30-sparky-zram.rules"
python3 "$HERE/game-performance.py" "$WORK/helper/usr/bin/game-performance" "$NATIVE" "$WORK/performance"
for control in size sysctl; do
	if python3 "$HERE/power-defaults.py" "$WORK/kernel" "$NATIVE" "$WORK/negative-$control" --negative "$control"; then
		echo "Negative $control control unexpectedly passed"
		exit 1
	fi
done
printf '#!/bin/bash\nexec "$@"\n' >"$WORK/negative-helper"
chmod +x "$WORK/negative-helper"
if python3 "$HERE/game-performance.py" "$WORK/negative-helper" "$NATIVE" "$WORK/negative-helper-test"; then
	echo 'Negative helper control unexpectedly passed'
	exit 1
fi
python3 - "$WORK" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
expected = {'size': 'Wrong native zram size for 16384 MiB',
            'sysctl': 'Sysctl policy differs from the accepted reference',
            'helper-test': "'profile': 'balanced'"}
for name, failure in expected.items():
    result = json.loads((root / f'negative-{name}/results.json').read_text())
    assert failure in result['failure'], result
print('PASS all three negative controls failed for their expected reason')
PY
mkdir "$WORK/rebuild"
dpkg-source -x "$POWER_DEFAULTS_OUT/sparky-stereo-game-performance_0.1.0.dsc" "$WORK/rebuild/source"
OUT=$WORK/rebuild bash "$WORK/rebuild/source/build.sh"
dpkg-deb -x "$WORK/rebuild/sparky-stereo-game-performance_0.1.0_all.deb" "$WORK/rebuilt-helper"
diff -r "$WORK/helper/usr" "$WORK/rebuilt-helper/usr"
python3 "$HERE/../../lists/make-meta.py" 20261010 "$WORK/meta"
python3 - "$WORK" "$HELPER_DEB" <<'PY'
import json
import subprocess
import sys
from pathlib import Path
root, package = Path(sys.argv[1]), sys.argv[2]
for key, expected in {'Architecture': 'all', 'Version': '0.1.0',
                      'Depends': 'bash, power-profiles-daemon (>= 0.30)'}.items():
    assert subprocess.check_output(['dpkg-deb', '-f', package, key], text=True).strip() == expected
control = (root / 'meta/task-sparky-stereo-gamer/DEBIAN/control').read_text()
fields = dict(line.split(': ', 1) for line in control.splitlines() if ': ' in line and not line.startswith(' '))
assert 'sparky-stereo-game-performance' in fields['Recommends'].split(', ')
assert 'sparky-stereo-kernel-settings' in (root / 'meta/sparky-stereo-system/DEBIAN/control').read_text()
rule = (root / 'kernel/usr/lib/udev/rules.d/30-sparky-zram.rules').read_text()
active = [line for line in rule.splitlines() if line and not line.startswith('#')]
assert active == ['ACTION=="change", KERNEL=="zram0", ATTR{initstate}=="1", SYSCTL{vm.swappiness}="150"']
(root / 'package-results.json').write_text(json.dumps({'checksums': 'passed', 'native_source_rebuild_payload': 'identical',
    'helper_dependencies': 'passed', 'gamer_task_recommends_helper': True,
    'system_task_depends_kernel_settings': True, 'zram_udev_reference': 'passed'}, indent=2) + '\n')
print('PASS package metadata, source payload, task references and zram udev policy')
PY
python3 "$HERE/guest-tty-test.py" -v
echo 'PASS milestone 6 container checks; guest VT measurements remain for the main session'
