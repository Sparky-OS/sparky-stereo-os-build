#!/bin/bash
# Sparky Stereo OS: qt6-base 6.11.2+dfsg-5+stereo3d14, the +stereo3d13 source package with the documentation build after the
# module header syncs, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23, +stereo3d13 2026/10/30, +stereo3d14 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the plain +stereo3d13 source
# package, /prev the earlier +lc1 builds.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s14 && cd s14
# the plain +stereo3d13 source package: sparky-os/repo/plain-from-lc.py on the published +stereo3d13+lc1 source (the same
# bytes each time it is made); its .dsc pins the files
echo '51524e59abfab964ab0f3de9e5093cdfb558c7623d38a3f89ad99ff56b4fbe99  /src/qt6-base_6.11.2+dfsg-5+stereo3d13.dsc' | sha256sum -c
cp /src/qt6-base_6.11.2+dfsg-5+stereo3d13.dsc /src/qt6-base_6.11.2+dfsg-5+stereo3d13.debian.tar.xz /src/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-base_6.11.2+dfsg-5+stereo3d13.dsc t >/dev/null
cd t
# The documentation build (binary-indep) runs before the libraries in one dpkg-buildpackage run. Its qdoc steps depend on
# sync_all_public_headers, syncqt -all, which scans every header of the source tree (the Android JNI headers and
# qconfig-bootstrapped.h too) and writes each module header into the build tree; the module's own syncqt run writes the
# same file and copies it to the staging folder that is installed. In +stereo3d13 the two ran at once and the staged QtCore
# took the scan's includes (ORDER 308). The module syncs now finish first.
python3 - <<'RULES'
from pathlib import Path
p = Path('debian/rules')
old = """override_dh_auto_build-indep:
ifeq (,$(filter nodoc,$(DEB_BUILD_OPTIONS) $(DEB_BUILD_PROFILES)))
\tdh_auto_build -- docs
endif
"""
new = """override_dh_auto_build-indep:
ifeq (,$(filter nodoc,$(DEB_BUILD_OPTIONS) $(DEB_BUILD_PROFILES)))
\t# docs runs syncqt -all (sync_all_public_headers), which writes every module header in the build tree; the
\t# module's own syncqt writes the same file and stages it for installation, so it finishes first
\tdh_auto_build -- sync_headers
\tdh_auto_build -- docs
endif
"""
rules = p.read_text()
assert rules.count(old) == 1, 'override_dh_auto_build-indep is not the +stereo3d13 one'
p.write_text(rules.replace(old, new))
RULES
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d14.txt').read_text()
assert entry.startswith('qt6-base (6.11.2+dfsg-5+stereo3d14) unstable;'), entry[:60]
assert p.read_text().startswith('qt6-base (6.11.2+dfsg-5+stereo3d13) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s14/qt6-base_6.11.2+dfsg-5+stereo3d14.dsc ../s14/qt6-base_6.11.2+dfsg-5+stereo3d14.debian.tar.xz ../s14/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-base_6.11.2+dfsg-5+stereo3d14.dsc /work/lc/source >/dev/null
cd /work/lc/source
# The same source-consumer plan as the published +stereo3d13+lc1 (sparky-os/release/run-native-batch.py).
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 6.11.2+dfsg-5+stereo3d14+lc1 --toolkit /toolkit \
	--preserve-source 'src/*_p.h' 'Qt syncqt reads the private-API warning comments, including We mean it.; retain its input headers exactly' \
	--preserve-source 'tests/*' 'Qt test inputs include deliberate comment/splice and invalid-syntax fixtures consumed as text by qmake and moc; preserve the upstream test corpus while projecting production source' \
	--preserve-source 'src/corelib/global/qoperatingsystemversion.h' 'Qt syncqt generates a different public-header set after textual projection; retain this input exactly, verified by the authored/projected syncqt comparison'
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
