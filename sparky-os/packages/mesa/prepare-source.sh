#!/bin/bash
# Prepare one source package from the published source, retaining its Lean Code pipeline.
set -euo pipefail
source_dir=${1:?directory containing the published +stereo3d16+lc1 source package}
work=${2:?empty output directory}
recipe=$(cd "$(dirname "$0")" && pwd)
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p "$work"
test -z "$(ls -A "$work")"
source_dir=$(cd "$source_dir" && pwd)
work=$(cd "$work" && pwd)
cd "$work"
echo 'fcc8222d839de851733c8b063944f76844dbf663ec48567383db703d295861f5  '"$source_dir/mesa_26.1.6-1+stereo3d16+lc1.dsc" | sha256sum -c
cp "$source_dir/mesa_26.1.6.orig.tar.xz" .
dpkg-source -x "$source_dir/mesa_26.1.6-1+stereo3d16+lc1.dsc" source
for patch in 0027-dri3-first-resize-and-xwindow-stereo-lifetime.patch \
             0028-dri3-stereo-front-views-and-first-declaration.patch; do
    cp "$recipe/patches/$patch" source/debian/patches/
    printf '%s\n' "$patch" >> source/debian/patches/series
done
python3 - "$recipe" <<'PY'
from pathlib import Path
from email.utils import formatdate
import sys
recipe = Path(sys.argv[1])
root = Path('source')
p = root / 'debian/changelog'
entry = (recipe / 'changelog-stereo3d17.txt').read_text()
assert entry.startswith('mesa (26.1.6-1+stereo3d17) unstable;')
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
dch --newversion 26.1.6-1+stereo3d17+lc1 --distribution UNRELEASED \
    'Retain the published source-consumer preservation plan and verified native/payload Lean Code pipeline.'
dpkg-source --before-build .
cd ..
dpkg-source -b source
