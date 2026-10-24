#!/bin/bash
# /work contains the once-prepared source; /prev contains the prior package set.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
export SPARKY_LC_PREVIOUS_DIR=/prev
cd /work/source
dpkg-checkbuilddeps
dpkg-buildpackage -us -uc -j4
cd /work
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
PYTHONPATH=/toolkit python3 -m lean.release check-link ./*+lc1_*.deb --previous-dir /prev
