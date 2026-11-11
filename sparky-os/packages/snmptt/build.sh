#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: Debian's snmptt 1.5-3 with the dependency its default needs (ORDER 346c, item 140: "Perl Net::IP
# missing, a missing Depends"). snmptt.ini ships ipv6_enable = 1, snmptt's own default, and with it snmptt stops with
# "Could not load the Perl module Net::IP!" unless libnet-ip-perl is installed; snmptt's documentation lists Net::IP
# (deb: libnet-ip-perl) as required for IPv6. Debian's packaging stays as Debian has it; we add the Depends, our
# changelog entry and the maintainer fields, then Lean Code at +lc1.
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names the unmodified Debian snmptt_1.5-3.dsc and its adjacent archives. With LINK_GATE_ON_HOST=1 the
# disposable build tree leaves Lean Code's link gate out (it needs bubblewrap and the archive-qualified universe), and
# `python3 -m lean.release check-link` must then run on the built archives where those are.
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
: "${LEAN_TOOLKIT:=$(cd "$HERE/../.." && pwd)}"
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian snmptt_1.5-3.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
VERSION=1.5-3+sparky1
printf '%s  %s\n' 2395db19d8626bca29d3688d54c41909b0f156ae810f7fde083f4ba66b5ef296 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/source" ]
mkdir -p "$BUILD_ROOT" "$OUT/source" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/snmptt_1.5.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
python3 - <<'PY'
import re
from pathlib import Path
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old, 1)
text = text.replace('Homepage: http://www.snmptt.org/',
                    'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues', 1)
# the binary package's Depends: libnet-ip-perl first, the rest as Debian has it
stanza = text.index('\nPackage: snmptt\n')
match = re.compile(r'^Depends:', re.M).search(text, stanza)
assert match, 'no Depends in the snmptt stanza'
text = text[:match.end()] + ' libnet-ip-perl,' + text[match.end():]
path.write_text(text)
PY
grep -A3 '^Package: snmptt$' debian/control | grep -q 'Depends: libnet-ip-perl,'
dch --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'snmptt.ini ships ipv6_enable = 1, which needs Net::IP: depend on libnet-ip-perl (snmptt stopped with "Could not load the Perl module Net::IP!").'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-source -b . >/dev/null
cd "$BUILD_ROOT"
cp snmptt_${VERSION}.dsc snmptt_${VERSION}.debian.tar.* snmptt_1.5.orig.tar.* "$OUT/authored/"
dpkg-source -x "snmptt_${VERSION}.dsc" lean-source >/dev/null
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare lean-source "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" lean-source
(cd lean-source && dpkg-source -b . >/dev/null)
dpkg-source -x "snmptt_${VERSION}+lc1.dsc" build >/dev/null
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
cp "$BUILD_ROOT"/snmptt_${VERSION}+lc1.dsc "$BUILD_ROOT"/snmptt_${VERSION}+lc1.debian.tar.* "$BUILD_ROOT"/snmptt_1.5.orig.tar.* "$OUT/source/"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
