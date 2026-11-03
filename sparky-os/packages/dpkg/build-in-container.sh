#!/bin/bash
# Sparky Stereo OS: dpkg 1.23.11+stereo3d1, Debian's dpkg 1.23.11 with the Lean Code shared-file check, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Runs as root inside a clean Debian testing build container; build.sh starts it. /work is the job folder (empty), /src
# Debian's dpkg_1.23.11.dsc and dpkg_1.23.11.tar.xz as apt-get source downloads them, /toolkit the build tree's sparky-os
# folder and /tools this folder. dpkg-buildpackage runs dpkg's own test suite (make check: the unit, autotest and Perl
# tests); then the functional test suite (tests/, the one with the Multi-Arch cases) runs against the build tree. Lean
# Code's link and start gate runs afterwards on the built archives, outside the build (LINK_GATE_ON_HOST, as snmptt's
# recipe does).
# Last update 2026/11/03
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
UPSTREAM=1.23.11
VERSION=$UPSTREAM+stereo3d1
cd /work
echo "4511c16a3bbbd3a88982408e2e5e5c471dc5f4a49eaa9b2cb93bf3e8c067fa78  /src/dpkg_$UPSTREAM.dsc" | sha256sum -c
mkdir s1 && cd s1
cp /src/dpkg_$UPSTREAM.dsc /src/dpkg_$UPSTREAM.tar.xz .
dpkg-source -x dpkg_$UPSTREAM.dsc t >/dev/null
cd t
# the patch (git format-patch of the commit on dpkg's 1.23.11 tag): the code and its functional test
for p in /tools/patches/*.patch; do
	patch -p1 --no-backup-if-mismatch <"$p"
done
grep -q 'leancode_shared_projection' src/main/archives.c
grep -q 'test-coinstall-shared-files-leancode:' tests/t-multiarch/Makefile
# dpkg --version names the build: configure takes the version from .dist-version (build-aux/get-version), and dh's
# autoreconf regenerates configure
printf '%s\n' "$VERSION" >.dist-version
python3 - <<'PY'
from pathlib import Path
import email.utils
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: ')) + '\n'
assert text.count(old) == 1
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old)
old = next(line for line in text.splitlines() if line.startswith('Homepage: ')) + '\n'
assert text.count(old) == 1
text = text.replace(old, 'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues\n')
# dpkg's own stanza: the contract dpkg-stereo depends on
stanza = text.index('\nPackage: dpkg\n')
end = text.find('\n\n', stanza + 1)
end = len(text) if end < 0 else end
body = text[stanza:end]
assert '\nProvides:' not in body, 'dpkg already provides something: merge by hand'
desc = body.index('\nDescription:')
text = text[:stanza] + body[:desc] + '\nProvides: dpkg-lean-code (= 1)' + body[desc:] + text[end:]
path.write_text(text)
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('dpkg (1.23.11+stereo3d1) mashtabba;'), entry[:60]
assert p.read_text().startswith('dpkg (1.23.11) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
             + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
PY
grep -A12 '^Package: dpkg$' debian/control | grep -E '^(Package|Provides|Essential)'
cd ..
dpkg-source -b t >/dev/null
rm -rf t
# the Lean Code source
mkdir -p /work/lc && cd /work/lc
cp ../s1/dpkg_$VERSION.dsc ../s1/dpkg_$VERSION.tar.xz .
dpkg-source -x dpkg_$VERSION.dsc /work/lc/authored >/dev/null
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/authored $VERSION+lc1 --toolkit /toolkit
(cd /work/lc/authored && dpkg-source -b . >/dev/null)
dpkg-source -x dpkg_$VERSION+lc1.dsc /work/lc/source >/dev/null
n=$(grep -c 'python3 -m lean.debhelper --provenance' /work/lc/source/debian/rules)
[ "$n" = 1 ]
# payload-preserve.json: the five Perl modules lean's Perl handler cannot qualify (their qr{...}x patterns carry whole-line
# comments, which are pattern text B::Deparse prints) stay as authored, each with its reason in the lc1 manifest
cat >/work/builddeb-nogate.py <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / 'debian/sparky-lean-toolkit'))
from lean import debhelper, package, release
plans = json.loads(Path('/tools/payload-preserve.json').read_text())
build_tree = release.build_tree
def preserving(staging, out, preserve=None):
    name = package.identity(package.control(staging))[0]
    return build_tree(staging, out, preserve=plans.get(name, preserve))
release.build_tree = preserving
debhelper.link_gate = lambda built: print('link gate after the build: lean.release check-link', ' '.join(p.name for p in built))
debhelper.build(root, root / 'debian/sparky-lean-toolkit/provenance.sh')
PY
sed -i "s|^\tPYTHONPATH=\$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance .*\$|\tpython3 /work/builddeb-nogate.py \$(CURDIR)|" /work/lc/source/debian/rules
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the functional test suite runs under eatmydata, as dpkg's own autopkgtest does (debian/tests/test-func)
apt-get -y --no-install-recommends install eatmydata >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' gcc dpkg-dev debhelper po4a libmd-dev python3 >/work/build-toolchain.txt
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
# dpkg's test suite (make check) runs inside dpkg-buildpackage
runuser -u builder -- dpkg-buildpackage -us -uc -j4 >/work/build.log 2>&1
# the functional test suite against the build tree's programs, as non-root (dpkg's own default mode); dpkg-build-tree has
# the programs, the source tree the shell library dpkg-maintscript-helper reads from DPKG_DATADIR (src/sh)
set +e
runuser -u builder -- env -C /work/lc/source/tests eatmydata make test DPKG_BUILDTREE=/work/lc/source/build-tree DPKG_DATADIR=/work/lc/source/src >/work/functional.log 2>&1
echo "functional test suite: exit $?" >/work/functional.exit
set -e
cat /work/functional.exit
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
