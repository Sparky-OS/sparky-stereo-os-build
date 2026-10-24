#!/bin/bash
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
export PYTHONPATH=/toolkit
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
cd /work
original=/new/media-gpu-route-tools_0.1.0+lc1_amd64.deb
python3 -m lean.release check-debs "$original" > check-debs-positive.log 2>&1
python3 -m lean.release check-link "$original" /new/libmedia-gpu-route0_0.1.0+lc1_amd64.deb > check-link-positive.log 2>&1
dpkg-deb -R "$original" unmarked >/dev/null
python3 - <<'PY'
from pathlib import Path
p=Path('unmarked/DEBIAN/control')
p.write_text(''.join(line for line in p.read_text().splitlines(keepends=True) if not line.startswith('Sparky-Lean-Code:')))
PY
dpkg-deb --root-owner-group -b unmarked unmarked.deb >/dev/null
set +e
python3 -m lean.release check-debs unmarked.deb > check-debs-negative.log 2>&1
code=$?
set -e
printf '%s\n' "$code" > check-debs-negative.exit
[ "$code" != 0 ]
dpkg-deb -R "$original" broken >/dev/null
mkdir missing
printf 'int order223_needed(void) { return 0; }\n' > missing.c
printf 'extern int order223_needed(void); int main(void) { return order223_needed(); }\n' > broken.c
gcc -shared -fPIC missing.c -Wl,-soname,liborder223-missing.so -o missing/liborder223-missing.so
gcc broken.c -Lmissing -lorder223-missing -o broken/usr/bin/media-gpu-route-query
python3 - <<'PY'
from pathlib import Path
p=Path('broken/DEBIAN/control')
p.write_text(p.read_text().replace('Version: 0.1.0+lc1','Version: 0.1.1+lc1'))
PY
dpkg-deb --root-owner-group -b broken broken.deb >/dev/null
set +e
python3 -m lean.release check-link --previous-dir /new broken.deb > check-link-negative.log 2>&1
code=$?
set -e
printf '%s\n' "$code" > check-link-negative.exit
[ "$code" != 0 ]
echo 'Both archive gates accepted the cohort control and rejected their negative control'
