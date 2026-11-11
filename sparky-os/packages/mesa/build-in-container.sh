#!/bin/bash
# WORK contains the once-prepared source; PREVIOUS contains the prior package set.
# Defaults retain the build.sh container layout.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
export DH_OPTIONS='--builddirectory=build/ --buildsystem=meson'
work=${1:-/work}
export SPARKY_LC_PREVIOUS_DIR=${2:-/prev}
toolkit=${3:-/toolkit}
cd "$work/source"
dpkg-checkbuilddeps
dpkg-buildpackage -B -us -uc -j4
cd "$work"
PYTHONPATH="$toolkit" python3 -m lean.release check-debs ./*+lc1_*.deb
PYTHONPATH="$toolkit" python3 -m lean.release check-link ./*+lc1_*.deb --previous-dir "$SPARKY_LC_PREVIOUS_DIR"
