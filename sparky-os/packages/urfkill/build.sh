#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/08
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: Debian's urfkill 0.5.0-8 with the session tracking it was meant to have (ORDER 460; Debian bug #1152866,
# our report with this patch). urfkill 0.5.0-3 switched to logind, 0.5.0-7 made it depend on default-logind | logind, and
# 0.5.0-8 lost the trailing backslash in debian/rules, which left "--with-session-tracking=systemd" commented out; configure
# then takes its default, ConsoleKit, and urfkilld stops at "failed to setup session checker" on a system that has
# systemd-logind and no ConsoleKit. Debian's packaging stays as Debian has it: we restore the option, add our changelog entry
# and the maintainer fields, then Lean Code at +lc1. The edition keeps this build until Debian ships a urfkill that asks
# logind again (0.5.0-7.3, in stable, does).
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names the unmodified Debian urfkill_0.5.0-8.dsc and its adjacent archives. With LINK_GATE_ON_HOST=1 the
# disposable build tree leaves Lean Code's link gate out (it needs bubblewrap and the archive-qualified universe), and
# `python3 -m lean.release check-link` must then run on the built archives where those are.
# Last update 2026/11/08
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
: "${LEAN_TOOLKIT:=$(cd "$HERE/../.." && pwd)}"
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian urfkill_0.5.0-8.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
VERSION=0.5.0-8+sparky1
printf '%s  %s\n' 7947fe801ebb61c62a892949a0451695e03ed5875635fa6ab7dc0ab40703be32 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/source" ]
mkdir -p "$BUILD_ROOT" "$OUT/source" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/urfkill_0.5.0.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
python3 - <<'PY'
from pathlib import Path
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old, 1)
if '\nBugs:' not in text:
    text = text.replace('\nStandards-Version:', '\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues\nStandards-Version:', 1)
path.write_text(text)
# debian/rules: the line before the option lost its backslash and the option is a comment (Debian bug #1152866)
path = Path('debian/rules')
text = path.read_text()
broken = '\t\t--libexecdir=\\$${libdir}/urfkill \n\t\t#--with-session-tracking=systemd\n'
fixed = '\t\t--libexecdir=\\$${libdir}/urfkill \\\n\t\t--with-session-tracking=systemd\n'
assert text.count(broken) == 1, 'debian/rules is not the 0.5.0-8 text this fix was written for'
path.write_text(text.replace(broken, fixed))
PY
grep -q '^	*--with-session-tracking=systemd$' debian/rules
dch --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'debian/rules: pass --with-session-tracking=systemd again (the line before it lost its trailing backslash in 0.5.0-8 and the option was a comment, so urfkilld asked ConsoleKit and stopped with "failed to setup session checker" on a system that runs systemd-logind; Debian bug #1152866).'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-source -b . >/dev/null
cd "$BUILD_ROOT"
cp urfkill_${VERSION}.dsc urfkill_${VERSION}.debian.tar.* urfkill_0.5.0.orig.tar.* "$OUT/authored/"
dpkg-source -x "urfkill_${VERSION}.dsc" lean-source >/dev/null
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare lean-source "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" lean-source
(cd lean-source && dpkg-source -b . >/dev/null)
dpkg-source -x "urfkill_${VERSION}+lc1.dsc" build >/dev/null
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
cp "$BUILD_ROOT"/urfkill_${VERSION}+lc1.dsc "$BUILD_ROOT"/urfkill_${VERSION}+lc1.debian.tar.* "$BUILD_ROOT"/urfkill_0.5.0.orig.tar.* "$OUT/source/"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
