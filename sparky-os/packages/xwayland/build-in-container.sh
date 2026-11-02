#!/bin/bash
# Build only binaries from the once-prepared descriptor; use the current release gate.
set -euo pipefail
work=${1:?prepared source directory}
previous=${2:?published predecessor packages}
toolkit=${3:?current release toolkit with check-link}
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
export DH_OPTIONS='--builddirectory=build/ --buildsystem=meson'
export SPARKY_LC_PREVIOUS_DIR="$previous"
cd "$work/source"
dpkg-checkbuilddeps
dpkg-buildpackage -B -us -uc -j4
cd "$work"
PYTHONPATH="$toolkit" python3 -m lean.release check-debs ./*+lc1_*.deb
PYTHONPATH="$toolkit" python3 -m lean.release check-link ./*+lc1_*.deb --previous-dir "$previous"
