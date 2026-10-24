# Sparky Stereo OS, ORDER 247: rebuild of lane 41's source package inside the published-image container (mounts: /stage staged debs, /in the lc1 .dsc set, /toolkit sparky-os, /out). Created by Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p /repo && cd /repo && cp /stage/*/*.deb . && dpkg-scanpackages -m . 2>/dev/null > Packages
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/staged.list
printf 'Package: *\nPin: origin ""\nPin-Priority: 1002\n' > /etc/apt/preferences.d/staged
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends install devscripts quilt xz-utils >/dev/null 2>&1
mkdir -p /out/lc && cd /out/lc && cp /in/* .
dpkg-source -x gwenview_26.04.0-1+stereo3d7+lc1.dsc src >/dev/null 2>&1
cd src
# step the lc1 stub back to the plain +stereo3d7 entry, then open +stereo3d8
python3 - <<'PY'
import re
s=open('debian/changelog').read()
s=s.replace('gwenview (4:26.04.0-1+stereo3d7+lc1) UNRELEASED','gwenview (4:26.04.0-1+stereo3d7) unstable',1)
s=s.replace("  * Apply verified native Lean Code before compilation and qualified lc1\n    payload assembly; retain exact authored source and HR companions.\n","",1)
open('debian/changelog','w').write(s)
r=open('debian/rules').read(); m='# Distribution-only processing; authored source remains in the source archive.'
assert r.count(m)==1; open('debian/rules','w').write(r.split(m)[0].rstrip('\n')+'\n')
PY
rm -rf debian/sparky-lean-toolkit
cp /patch/gv8-patch.patch debian/patches/stereo-photo-mimetypes.patch
echo stereo-photo-mimetypes.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a -q >/dev/null || true
quilt applied | tail -1
dch --newversion 4:26.04.0-1+stereo3d8 --distribution unstable 'List image/x-jps, image/x-mpo and image/x-pns in the MimeType of Gwenview'"'"'s desktop entry and part, so Open With and the default list Gwenview for the stereo picture types directly (the sparky-stereo-look 20261024.1 default names it).'
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 4:26.04.0-1+stereo3d8+lc1 --toolkit /toolkit
head -12 debian/changelog
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 || { tail -20 /out/build-dep.log; exit 1; }
useradd --create-home --uid 1000 builder 2>/dev/null || true
chown -R builder /out
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x gwenview_26.04.0-1+stereo3d8+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/stage/gwenview dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || { echo BUILD-FAILED; tail -30 /out/build.log; }
cd /out/lc && PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
