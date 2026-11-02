#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: Debian's pkcs11-proxy 0.4.1-5 with the library its daemon's default needs (ORDER 346c, item 140:
# pkcs11-daemon failed for "no /usr/lib/softhsm/libsofthsm2.so"). /etc/default/pkcs11-daemon ships
# PKCS11_LIB=/usr/lib/softhsm/libsofthsm2.so, SoftHSM's library, and pkcs11-daemon stops with "couldn't open library"
# unless libsofthsm2 is installed. Debian's packaging stays as Debian has it; we add the Depends, our changelog entry
# and the maintainer fields, then Lean Code at +lc1.
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names the unmodified Debian pkcs11-proxy_0.4.1-5.dsc and its adjacent archives. With LINK_GATE_ON_HOST=1 the
# disposable build tree leaves Lean Code's link gate out (it needs bubblewrap and the archive-qualified universe), and
# `python3 -m lean.release check-link` must then run on the built archives where those are.
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${LEAN_TOOLKIT:=$(cd "$HERE/../.." && pwd)}"
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian pkcs11-proxy_0.4.1-5.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
VERSION=0.4.1-5+sparky1
printf '%s  %s\n' 6bb80088255533ee32a07f5e9706fcb2825917fdd86543492fd88e32918ff4ce "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/source" ]
mkdir -p "$BUILD_ROOT" "$OUT/source" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/pkcs11-proxy_0.4.1.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
python3 - <<'PY'
import re
from pathlib import Path
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old, 1)
# Debian's source names no Homepage: ours and the edition's tracker after the Section line
text = text.replace('Section: net\n', 'Section: net\nHomepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues\n', 1)
# pkcs11-daemon's Depends: libsofthsm2 first, the rest as Debian has it
stanza = text.index('\nPackage: pkcs11-daemon\n')
match = re.compile(r'^Depends:', re.M).search(text, stanza)
assert match, 'no Depends in the pkcs11-daemon stanza'
text = text[:match.end()] + ' libsofthsm2,' + text[match.end():]
path.write_text(text)
PY
grep -A4 '^Package: pkcs11-daemon$' debian/control | grep -q 'Depends: libsofthsm2,'
dch --newversion "$VERSION" --distribution mashtabba \
	'pkcs11-daemon: /etc/default/pkcs11-daemon names SoftHSM'"'"'s library as PKCS11_LIB: depend on libsofthsm2 (the daemon stopped with "couldn'"'"'t open library").'
dpkg-source -b . >/dev/null
cd "$BUILD_ROOT"
cp pkcs11-proxy_${VERSION}.dsc pkcs11-proxy_${VERSION}.debian.tar.* pkcs11-proxy_0.4.1.orig.tar.* "$OUT/authored/"
dpkg-source -x "pkcs11-proxy_${VERSION}.dsc" lean-source >/dev/null
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare lean-source "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
(cd lean-source && dpkg-source -b . >/dev/null)
dpkg-source -x "pkcs11-proxy_${VERSION}+lc1.dsc" build >/dev/null
if [ "${LINK_GATE_ON_HOST:-0}" = 1 ]; then
	n=$(grep -c 'python3 -m lean.debhelper --provenance' build/debian/rules)
	[ "$n" = 1 ]
	cat >"$BUILD_ROOT/builddeb-nogate.py" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / 'debian/sparky-lean-toolkit'))
from lean import debhelper
debhelper.link_gate = lambda built: print('link gate on the host: lean.release check-link', ' '.join(p.name for p in built))
debhelper.build(root, root / 'debian/sparky-lean-toolkit/provenance.sh')
PY
	sed -i "s|^\tPYTHONPATH=\$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance .*\$|\tpython3 $BUILD_ROOT/builddeb-nogate.py \$(CURDIR)|" build/debian/rules
fi
(cd build && dpkg-buildpackage -us -uc -b -j4)
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.release check-debs "$BUILD_ROOT"/*+lc1_*.deb
cp "$BUILD_ROOT"/*+lc1_*.deb "$OUT/"
cp "$BUILD_ROOT"/pkcs11-proxy_${VERSION}+lc1.dsc "$BUILD_ROOT"/pkcs11-proxy_${VERSION}+lc1.debian.tar.* "$BUILD_ROOT"/pkcs11-proxy_0.4.1.orig.tar.* "$OUT/source/"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
