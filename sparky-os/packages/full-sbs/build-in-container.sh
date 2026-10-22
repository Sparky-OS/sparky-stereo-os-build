#!/bin/bash
# Sparky Stereo OS: one package of the full side by side round (each eye handed over at its own resolution), built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. Environment: PKG (source package name).
# /work is the job folder, /src the published plain sources, /pub the signed tree, /new the debs built earlier in the round,
# /prev the earlier +lc1 builds, /patches this recipe's patches, /changelog its entries, /fork the release clone (stereo-layer, stereo-declare).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/new ./\n' > /etc/apt/sources.list.d/edition-new.list
printf 'deb [trusted=yes] file:/pub mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
git config --global safe.directory '*'
cd /work
mkdir plain-in plain && cd plain-in
extra=()
patchsub=
case "$PKG" in
mpv-dmo)          BASE='mpv-dmo_0.41.0-dmo9+stereo3d3';          NEWV='1:0.41.0-dmo9+stereo3d4' ;;
mpvqt)            BASE='mpvqt_1.2.0-3+stereo3d2';                NEWV='1.2.0-3+stereo3d3' ;;
mlt)              BASE='mlt_7.40.0-1+stereo3d3';                 NEWV='7.40.0-1+stereo3d4' ;;
kdenlive)         BASE='kdenlive_26.08.1-1+stereo3d3';           NEWV='26.08.1-1+stereo3d4' ;;
qt6-multimedia)   BASE='qt6-multimedia_6.11.2-3+stereo3d6';      NEWV='6.11.2-3+stereo3d7'
                  extra+=(--preserve-source 'src/*_p.h' 'Qt syncqt reads the private-API warning comments, including We mean it.; retain its input headers exactly')
                  extra+=(--preserve-source 'src/3rdparty/eigen/*' 'Debian links system Eigen through /usr/include/eigen3; the unused vendored tree includes PowerPC target pragmas that cannot be qualified by the x86 compiler') ;;
spice-gtk)        BASE='spice-gtk_0.43+git20261010.77a4ac6-1+stereo3d2'; NEWV='0.43+git20261010.77a4ac6-1+stereo3d3'
                  patchsub=stereo3d; extra+=(--build-dependency gi-docgen) ;;
karton)           BASE='karton_0.1~prealpha+git20260905.08e13cf-1+stereo3d2'; NEWV='0.1~prealpha+git20260905.08e13cf-1+stereo3d3'
                  patchsub=stereo3d ;;
qemu)             BASE='qemu_11.1.2+ds-1+stereo3d4';             NEWV='1:11.1.2+ds-3+stereo3d6'; patchsub=stereo3d ;;
stereo-layer)     NEWV='1.10.0-1'; ORIG=stereo-layer_1.10.0.orig.tar.xz; PREFIX=stereo-layer-1.10.0; REV=release-1.10.0 ;;
stereo-declare)   NEWV='1.3.1-1';  ORIG=stereo-declare_1.3.1.orig.tar.xz; PREFIX=stereo-declare-1.3.1; REV=release-1.3.1 ;;
*) echo "unknown package $PKG" >&2; exit 2 ;;
esac

# 1. The plain source package (the one the +lc1 source is prepared from).
case "$PKG" in
stereo-layer|stereo-declare)
    mkdir /work/export && git -C /fork archive --format=tar --prefix="$PREFIX/" "$REV" | tar -x -C /work/export
    cp -a "/work/export/$PREFIX/debian" /work/debian-export
    rm -rf "/work/export/$PREFIX/debian"
    stamp=$(git -C /fork log -1 --format=%ct "$REV")
    tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$stamp" -C /work/export -cf - "$PREFIX" | xz -9e > "$ORIG"
    tar -xf "$ORIG"
    cp -a /work/debian-export "$PREFIX/debian"
    dpkg-source -b "$PREFIX" >/dev/null
    rm -rf "$PREFIX"
    ;;
qemu)
    apt-get -y update >/dev/null 2>&1
    sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
    apt-get -y update >/dev/null 2>&1
    apt-get source --download-only qemu=1:11.1.2+ds-3 >/dev/null 2>&1
    cp /src/qemu_11.1.2+ds-1+stereo3d4.debian.tar.xz /work/retained-stereo3d4.debian.tar.xz
    dpkg-source -x qemu_11.1.2+ds-3.dsc t >/dev/null
    python3 /toolkit/packages/qemu-stereo/rebase-debian.py t /work/retained-stereo3d4.debian.tar.xz
    ;;
*)
    cp /src/"$BASE".dsc /src/"$BASE".debian.tar.xz .
    for f in $(sed -n 's/^ [0-9a-f]\{32,\} [0-9]* \(.*\)$/\1/p' /src/"$BASE".dsc | grep -v -e debian.tar -e '\.dsc$'); do cp /src/"$f" .; done
    [ -f /src/"$(ls *.orig.tar.* | head -1)".asc ] && cp /src/"$(ls *.orig.tar.* | head -1)".asc .
    dpkg-source -x "$BASE".dsc t >/dev/null
    ;;
esac
if [ -d t ]; then
    cd t
    test "$(dpkg-parsechangelog -S Distribution)" != UNRELEASED
    dest=debian/patches${patchsub:+/$patchsub}
    mkdir -p "$dest"
    for p in /patches/"$PKG"/*.patch; do
        cp "$p" "$dest/"
        echo "${patchsub:+$patchsub/}$(basename "$p")" >> debian/patches/series
    done
    python3 - "$PKG" "$NEWV" <<'CHANGELOG'
import email.utils, sys
from pathlib import Path
pkg, version = sys.argv[1:]
entry = Path('/changelog/' + pkg + '.txt').read_text()
assert entry.startswith(pkg + ' (' + version + ') unstable;'), entry[:60]
p = Path('debian/changelog')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
    if [ "$PKG" = kdenlive ]; then
        grep -q 'libmlt7 (>= 7.40.0-1+stereo3d3)' debian/control
        sed -i 's/libmlt7 (>= 7.40.0-1+stereo3d3)/libmlt7 (>= 7.40.0-1+stereo3d4)/' debian/control
    fi
    cd ..
    dpkg-source -b t >/dev/null
    rm -rf t
    rm -f "${BASE:-none}".dsc "${BASE:-none}".debian.tar.xz
    [ "$PKG" != qemu ] || rm -f qemu_11.1.2+ds-3.dsc qemu_11.1.2+ds-3.debian.tar.xz
fi
ls
cp -a . /work/plain/

# 2. The Lean Code source from it, then the build with the link and start gate against the earlier +lc1 builds.
mkdir -p /work/lc && cd /work/lc
cp /work/plain/* .
dsc=$(ls *.dsc)
dpkg-source -x "$dsc" /work/lc/source >/dev/null
cd /work/lc/source
case "$PKG" in
qemu) python3 /toolkit/packages/qemu-stereo/prepare-lean.py /work/lc/source "$NEWV+lc1" ;;
*) PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$NEWV+lc1" --toolkit /toolkit "${extra[@]}" ;;
esac
if [ "$PKG" = spice-gtk ]; then
    python3 - <<'SPICE_DOCS'
from pathlib import Path
p = Path('debian/libspice-client-glib-2.0-dev.install')
s = p.read_text()
assert s.count('usr/share/gtk-doc') == 1
p.write_text(s.replace('usr/share/gtk-doc', 'usr/share/doc/SpiceClientGLib-2.0'))
p = Path('debian/libspice-client-gtk-3.0-dev.install')
with p.open('a') as f:
    f.write('usr/share/doc/SpiceClientGtk-3.0\n')
SPICE_DOCS
fi
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
