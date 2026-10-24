#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Uses the common build container mounts, without a device or desktop connection.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export PYTHONPATH=/toolkit DEBIAN_FRONTEND=noninteractive
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
base=/pub/pool/main/s/sparky-stereo-hardware
cd /work
cp "$base/sparky-stereo-hardware_0.1.10+lc1.dsc" "$base/sparky-stereo-hardware_0.1.10+lc1.tar.xz" .
dpkg-source -x sparky-stereo-hardware_0.1.10+lc1.dsc predecessor-source > prepare.log 2>&1
python3 - <<'PY'
import hashlib,json,shutil
from pathlib import Path
root=Path('/work')
old=root/'predecessor-source/authoring'
new=Path('/kit/sparky-stereo-hardware')
for name in ('lib/actions.sh','bin/sparky-stereo-hardware','debian/changelog','build.sh','README.md'):
    shutil.copy2(new/name,old/name)
# The published payload is rebuilt from retained authored inputs, not extracted binaries.
(root/'predecessor.json').write_text(json.dumps({'dsc':'sparky-stereo-hardware_0.1.10+lc1.dsc','sha256':hashlib.sha256((root/'sparky-stereo-hardware_0.1.10+lc1.dsc').read_bytes()).hexdigest()},indent=2)+'\n')
PY
OUT=/work bash /work/predecessor-source/authoring/build.sh > /work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*.deb > /work/check-debs.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-link --previous-dir /previous /work/*.deb > /work/check-link.log 2>&1
