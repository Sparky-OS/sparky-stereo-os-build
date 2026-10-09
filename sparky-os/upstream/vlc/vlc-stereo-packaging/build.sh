#!/bin/bash
# Builds vlc-stereo and vlc-stereo-plugin-pipewire. Run inside the build image (see README) as a normal user:
#   UP=/src (this repository folder, read-only)  WORK=/work (writable)  OUT=/out (writable)
set -eux
UP=${UP:-/src}; WORK=${WORK:-/work}; OUT=${OUT:-/out}; PK=$UP/vlc-stereo-packaging
VER=${VER:-3.0.24-1+stereo3d6}
export PK
rm -rf $WORK/src $WORK/pw $WORK/dl && mkdir -p $WORK/src $WORK/pw

# 1. Debian testing's vlc source, our patches as quilt patches on top of Debian's own
cd $WORK/src
apt-get source -qq vlc
cd vlc-*/
export QUILT_PATCHES=debian/patches
add() { cp "$1" "debian/patches/$2"; echo "$2" >> debian/patches/series; }
for p in $PK/patches/base/*.patch;          do add $p 3d-base-$(basename $p); done   # the three changes of the VLC 3d1 release
for p in $UP/0*.patch;                      do add $p 3d-$(basename $p); done        # the changes of VLC Stereo
add $UP/debian-branding/vlc-stereo-name.patch vlc-stereo-name.patch                   # the name
add $PK/patches/vlc-stereo-side-by-side.patch vlc-stereo-side-by-side.patch            # own settings and names beside the original VLC
quilt push -a

# 2. the source of Debian's vlc-plugin-pipewire (3-4, the upstream tarball), with our change
mkdir -p $WORK/dl && cd $WORK/dl
apt-get source --download-only -qq vlc-plugin-pipewire
cd $WORK/pw
tar -xf $WORK/dl/vlc-plugin-pipewire_*.orig.tar.xz --strip-components=1
for p in $PK/patches/pipewire/*.patch; do patch -p1 < $p; done
export PW=$WORK/pw

# 3. the packaging: Debian's control and rules turned into VLC Stereo's
cd $WORK/src/vlc-*/
python3 $PK/gen-debian.py
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
# one changelog entry per version of the file "changelog" of the packaging, oldest first (dch reads an environment variable
# called CHANGELOG as the name of the changelog file, so none is used here)
python3 - "$PK/changelog" "$VER" <<'PY' > $WORK/entries.sh
import sys, shlex
ver = sys.argv[2]; cur = None; ent = []
for l in open(sys.argv[1]):
    l = l.rstrip('\n')
    if l.startswith('== '):
        cur = [l[3:], []]; ent.append(cur)
    elif l and cur: cur[1].append(l)
for v, lines in ent:
    print('dch -v %s --distribution testing --force-distribution %s' % (shlex.quote(v), shlex.quote(lines[0])))
    for t in lines[1:]:
        print('dch -a %s' % shlex.quote(t))
    if v == ver: break
PY
. $WORK/entries.sh

# 4. the Debian source package of the build (.dsc, orig tarball, debian.tar.xz), made before the build so that no build product is in the tree
dpkg-buildpackage -S -uc -us -d
mkdir -p $OUT && cp ../vlc_$VER.dsc ../vlc_$VER.debian.tar.xz ../vlc_*.orig.tar.xz* $OUT/
[ -n "${SOURCE_ONLY:-}" ] && exit 0

# 5. the binary packages
DEB_BUILD_OPTIONS='parallel=5 nocheck' dpkg-buildpackage -b -uc -us
cp ../*.deb ../*.buildinfo ../*.changes $OUT/
