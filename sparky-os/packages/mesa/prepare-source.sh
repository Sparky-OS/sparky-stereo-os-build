#!/bin/bash
# Prepare one source package from the published source, retaining its Lean Code pipeline.
set -euo pipefail
source_dir=${1:?directory containing the published +stereo3d15+lc1 source package}
work=${2:?empty output directory}
recipe=$(cd "$(dirname "$0")" && pwd)
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p "$work"
test -z "$(ls -A "$work")"
source_dir=$(cd "$source_dir" && pwd)
work=$(cd "$work" && pwd)
cd "$work"
echo '868b9943e6cbe3725c7bee4098da3b5732720117a4d8c6e01eae619278aaa357  '"$source_dir/mesa_26.1.6-1+stereo3d15+lc1.dsc" | sha256sum -c
cp "$source_dir/mesa_26.1.6.orig.tar.xz" .
dpkg-source -x "$source_dir/mesa_26.1.6-1+stereo3d15+lc1.dsc" source
cp "$recipe/patches/0024-wayland-stereo-swapchain-lifetime.patch" source/debian/patches/
printf '%s\n' 0024-wayland-stereo-swapchain-lifetime.patch >> source/debian/patches/series
python3 - "$recipe" <<'PY'
from pathlib import Path
from email.utils import formatdate
import sys
recipe = Path(sys.argv[1])
root = Path('source')
p = root / 'debian/changelog'
entry = (recipe / 'changelog-stereo3d16.txt').read_text()
assert entry.startswith('mesa (26.1.6-1+stereo3d16) unstable;')
entry += '\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + formatdate(localtime=True) + '\n\n'
p.write_text(entry + p.read_text())
# debian/rules regenerates control from control.in; preserve the pipeline's build dependencies in both.
sys.path.insert(0, str(root / 'debian/sparky-lean-toolkit'))
from lean.debian_prepare import add_build_dependencies
for name in ('control.in', 'control'):
    p = root / 'debian' / name
    p.write_text(add_build_dependencies(p.read_text(), ['gcc', 'node-acorn', 'nodejs', 'perl', 'python3', 'python3-yaml']))
PY
cd source
dch --newversion 26.1.6-1+stereo3d16+lc1 --distribution UNRELEASED \
    'Retain the published source-consumer preservation plan and verified native/payload Lean Code pipeline.'
dpkg-source --before-build .
cd ..
dpkg-source -b source
