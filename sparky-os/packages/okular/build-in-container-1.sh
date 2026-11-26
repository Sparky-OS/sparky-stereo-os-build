#!/bin/bash
# Sparky Stereo OS: build okular 4:26.08.2-1+stereo3d1 through Lean Code, inside build-1.sh's container (queue row 121).
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# /src holds Debian's okular 4:26.08.2-1 source; /tools this recipe; /toolkit sparky-os; /repo the published edition; /extra
# .deb files installed before the build dependencies.
set -euo pipefail
cp /run/host-ca.crt /etc/ssl/certs/ca-certificates.crt
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
job=/work
version=4:26.08.2-1+stereo3d1
trap 'chown -R 1000:1000 "$job"' EXIT
: "${SPARKY_LC_ARCHIVE_CONFIG:?the signed archive configuration}" "${SPARKY_LC_SCRATCH:?the archive gate scratch directory}"
: "${SOURCE_DATE_EPOCH:?the recipe date from build-provenance.sh}"
printf 'deb [signed-by=/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cp /repo/sparky-stereo-repo.asc /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
mkdir -p "$job/lc" && cd "$job/lc"
cp /src/okular_26.08.2-1.dsc /src/okular_26.08.2-1.debian.tar.xz /src/okular_26.08.2.orig.tar.xz /src/okular_26.08.2.orig.tar.xz.asc .
sha256sum --check --quiet /tools/source.sha256
dpkg-source -x okular_26.08.2-1.dsc source > /dev/null
# the edition's patch, in a series of its own (Debian's okular carries none)
mkdir -p source/debian/patches
install -m644 /tools/patches/0001-pageview-paper-depth.patch source/debian/patches/
printf '%s\n' 0001-pageview-paper-depth.patch >> source/debian/patches/series
python3 - source/debian/control <<'CONTROL'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
# The paper's depth is drawn by the edition's Qt Widgets (qt6-base +stereo3d25, _q_stereo_depth_rects): a dependency of the
# feature, so okular, which carries the page view, depends on it.
old = 'Package: okular\nSection: graphics\nArchitecture: any\nDepends: okular-data (= ${source:Version}),\n'
assert s.count(old) == 1, 'the okular stanza changed'
s = s.replace(old, old + '         libqt6widgets6 (>= 6.11.2+dfsg-5+stereo3d25~),\n')
p.write_text(s)
CONTROL
python3 - source/debian/changelog <<'CHANGELOG'
import os, pathlib, sys
sys.path.insert(0, '/toolkit/repo')
import reproducible
p = pathlib.Path(sys.argv[1])
date = reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('okular (4:26.08.2-1+stereo3d1) unstable; urgency=medium\n\n'
             '  * On a stereo output the desk around the pages lies one step of depth\n'
             '    behind the window and the paper at the window\'s plane, its text,\n'
             '    pictures, annotations and selection with it and its shadow on the desk:\n'
             '    the page view declares them to the edition\'s Qt Widgets, which draws\n'
             '    them per eye in steps of the person\'s element limit (queue row 121).\n'
             '    On a 2D screen, in a window behind the active one or with the element\n'
             '    limit at 0, the view is drawn as before.\n\n'
             ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + date + '\n\n' + p.read_text())
CHANGELOG
apt-get -y update > "$job/apt-update.log" 2>&1
apt-get -y --no-install-recommends install devscripts quilt bubblewrap > "$job/setup.log" 2>&1
if compgen -G '/extra/*.deb' > /dev/null; then
    apt-get -y --no-install-recommends install /extra/*.deb > "$job/extra-install.log" 2>&1
fi
apt-get -y --no-install-recommends build-dep "$job/lc/source" > "$job/build-dep.log" 2>&1
dpkg-query -W qt6-base-dev libkf6coreaddons-dev libpoppler-qt6-dev > "$job/build-versions.txt"
cd "$job/lc/source"
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . "$version+lc1"
python3 /toolkit/repo/reproducible.py normalize "$SOURCE_DATE_EPOCH" debian
mkdir -p "$SPARKY_LC_SCRATCH"
# an image without a user of uid 1000 makes getent fail, which set -e and pipefail would take as the end of the build
build_user=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -z "$build_user" ]; then
    useradd --create-home --uid 1000 builder
    build_user=builder
fi
chown -R 1000:1000 "$job" "$SPARKY_LC_SCRATCH"
runuser -u "$build_user" -- env SPARKY_LC_PREVIOUS_SIBLINGS_FILE="$SPARKY_LC_PREVIOUS_SIBLINGS_FILE" \
    SPARKY_LC_SIBLINGS_FILE="$SPARKY_LC_SIBLINGS_FILE" SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
    dpkg-buildpackage -us -uc -sa -j4
cd "$job/lc"
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*26.08.2-1+stereo3d1+lc1*.deb
