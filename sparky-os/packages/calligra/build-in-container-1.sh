#!/bin/bash
# Sparky Stereo OS: build calligra 1:26.08.0+dfsg-1+stereo3d1 through Lean Code, inside build-1.sh's container (queue row 121).
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# /src holds Debian's calligra 1:26.08.0+dfsg-1 source; /tools this recipe; /toolkit sparky-os; /repo the published edition; /extra
# .deb files installed before the build dependencies.
set -euo pipefail
cp /run/host-ca.crt /etc/ssl/certs/ca-certificates.crt
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
job=/work
version=1:26.08.0+dfsg-1+stereo3d1
source_stem=calligra_${version#*:}+lc1
trap 'chown -R 1000:1000 "$job"' EXIT
: "${SPARKY_LC_ARCHIVE_CONFIG:?the signed archive configuration}" "${SPARKY_LC_SCRATCH:?the archive gate scratch directory}"
: "${SOURCE_DATE_EPOCH:?the recipe date from build-provenance.sh}"
printf 'deb [signed-by=/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cp /repo/sparky-stereo-repo.asc /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
mkdir -p "$job/lc" && cd "$job/lc"
prepare_source() {
cp /src/calligra_26.08.0+dfsg-1.dsc /src/calligra_26.08.0+dfsg-1.debian.tar.xz /src/calligra_26.08.0+dfsg.orig.tar.xz .
sha256sum --check --quiet /tools/source.sha256
dpkg-source -x calligra_26.08.0+dfsg-1.dsc source > /dev/null
# the edition's patch, in a series of its own (Debian's calligra carries none)
mkdir -p source/debian/patches
install -m644 /tools/patches/0001-words-paper-depth.patch source/debian/patches/
printf '%s\n' 0001-words-paper-depth.patch >> source/debian/patches/series
python3 - source/debian/control <<'CONTROL'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'Package: calligrawords\nArchitecture: any\nSection: text\nDepends: calligrawords-data (>= ${source:Version}),\n'
assert s.count(old) == 1, 'the calligrawords stanza changed'
s = s.replace(old, old + '         libqt6widgets6 (>= 6.11.2+dfsg-5+stereo3d26~),\n'
                         '         libqt6waylandclient6 (>= 6.11.2+dfsg-5+stereo3d26~),\n')
p.write_text(s)
CONTROL
python3 - source/debian/changelog <<'CHANGELOG'
import os, pathlib, sys
sys.path.insert(0, '/toolkit/repo')
import reproducible
p = pathlib.Path(sys.argv[1])
date = reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('calligra (1:26.08.0+dfsg-1+stereo3d1) unstable; urgency=medium\n\n'
             '  * Declare the Words desk and pages to Qt so the desk sits one step\n'
             '    behind the paper on stereo outputs (row 121). Preserve the canvas\n'
             '    shadow and follow the compositor as the window moves.\n\n'
             ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + date + '\n\n' + p.read_text())
CHANGELOG
}
if [ "${SPARKY_CALLIGRA_RESUME:-0}" = 1 ]; then
    sha256sum -c source-closure.sha256
    [ "$(dpkg-parsechangelog -l source/debian/changelog -S Version)" = "$version+lc1" ]
else
    prepare_source
fi
apt-get -y update > "$job/apt-update.log" 2>&1
apt-get -y --no-install-recommends install devscripts quilt bubblewrap > "$job/setup.log" 2>&1
qt_packages=()
for file in /extra/*.deb; do
    case $file in
        *-dbgsym_*|*-doc*|*-examples_*|*-lc-hr_*|*libqt6sql6-*) ;;
        *) qt_packages+=("$file") ;;
    esac
done
apt-get -y --no-install-recommends install "${qt_packages[@]}" > "$job/qt-install.log" 2>&1
# The edition pin would otherwise prefer its older Qt while resolving the build dependencies.
for file in "${qt_packages[@]}"; do dpkg-deb -f "$file" Package; done | xargs apt-mark hold >> "$job/qt-install.log"
apt-get -y --no-install-recommends build-dep "$job/lc/source" > "$job/build-dep.log" 2>&1
dpkg-query -W qt6-base-dev libqt6waylandclient6 okular-dev libpoppler-qt6-dev > "$job/build-versions.txt"
cd "$job/lc/source"
build_args=()
if [ "${SPARKY_CALLIGRA_RESUME:-0}" = 1 ]; then
    # Discard debhelper staging directories so Lean Code can project each package once.
    for package in $(dh_listpackages); do
        rm -rf "debian/$package" "debian/$package.debhelper.log" "debian/$package.substvars"
    done
    rm -rf debian/.debhelper debian/tmp debian/files
    # The compiled tree has Lean Code's projected sources. Keep the authored .dsc from before projection.
    build_args=(-b -nc)
else
    python3 /toolkit/repo/provenance-files.py . '0001-words-paper-depth.patch'
    PYTHONPATH=/toolkit python3 -m lean.debian_prepare . "$version+lc1"
    python3 /toolkit/repo/reproducible.py normalize "$SOURCE_DATE_EPOCH" debian
    build_args=("--hook-build=cd .. && sha256sum '$source_stem.dsc' '$source_stem.debian.tar.xz' calligra_26.08.0+dfsg.orig.tar.xz > source-closure.sha256")
fi
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
    dpkg-buildpackage "${build_args[@]}" -us -uc -sa -j4
if [ "${SPARKY_CALLIGRA_RESUME:-0}" = 1 ]; then
    output="../${source_stem}_$(dpkg-architecture -qDEB_HOST_ARCH)"
    runuser -u "$build_user" -- dpkg-genbuildinfo --build=full "-O$output.buildinfo"
    runuser -u "$build_user" -- dpkg-genchanges --build=full -sa "-O$output.changes"
fi
cd "$job/lc"
sha256sum -c source-closure.sha256
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*26.08.0+dfsg-1+stereo3d1+lc1*.deb
