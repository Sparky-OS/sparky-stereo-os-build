# Sparky Stereo OS, ORDER 250: digikam +stereo3d3, the published +stereo3d2+lc1 source with native file opening and both MimeType lists added as its own patch, built through Lean Code. Runs as root inside a container of the published set (Debian forky, deb-multimedia and the edition's repository pinned at 1001); mounts: /in the +stereo3d2+lc1 source package, /toolkit sparky-os, /patch the patch, /prev the +stereo3d2+lc1 .deb files for the link and start gate, /out. Created by Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
P=stereo-photo-mimetypes.patch
apt-get -y update >/dev/null 2>&1
apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade > /out/upgrade.log 2>&1
apt-get -y --no-install-recommends install devscripts quilt xz-utils >/dev/null 2>&1
mkdir -p /out/lc && cd /out/lc && cp /in/* .
dpkg-source -x digikam_9.1.0-1+stereo3d2+lc1.dsc src >/dev/null 2>&1
cd src
# back to the authored +stereo3d2: the Lean Code stage out of debian/rules and its toolkit out of debian/, its build
# dependencies once out of the front of Build-Depends (each preparation adds them again), and the published +lc1 entry
# marked released, so that dch opens a new entry instead of renaming it
python3 - <<'PY'
s=open('debian/changelog').read(); old='digikam (4:9.1.0-1+stereo3d2+lc1) UNRELEASED;'
assert s.startswith(old); s=s.replace(old,'digikam (4:9.1.0-1+stereo3d2+lc1) unstable;',1)
open('debian/changelog','w').write(s)
r=open('debian/rules').read(); m='# Distribution-only processing; authored source remains in the source archive.'
assert r.count(m)==1; open('debian/rules','w').write(r.split(m)[0].rstrip('\n')+'\n')
c=open('debian/control').read(); lc='Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml,\n debhelper-compat'
assert c.count(lc)==1; open('debian/control','w').write(c.replace(lc,'Build-Depends: debhelper-compat',1))
PY
rm -rf debian/sparky-lean-toolkit
cp /patch/digikam-open-files.patch debian/patches/
echo digikam-open-files.patch >> debian/patches/series
cp /patch/digikam-stereo-photo-mimetypes.patch debian/patches/$P
echo $P >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a -q
# These unchanged SONAME APIs are the ones used by the published +2 build.
cat > debian/shlibs.local <<'SHLIBS'
libMagick++-7.Q16 5 libmagick++-7.q16-5 (>= 8:7.1.2.33+dmo)
libMagickCore-7.Q16 10 libmagickcore-7.q16-10 (>= 8:7.1.2.33+dmo)
libstereo-layer 1 libstereo-layer1 (>= 1.9.0)
SHLIBS
dch --newversion 4:9.1.0-1+stereo3d3 --distribution unstable 'Open local files in the native digiKam preview without importing or changing them. List image/x-jps, image/x-mpo and image/x-pns directly in both digiKam and Showfoto desktop entries; retain Gwenview as the edition default and preserve the published dependency floors.'
head -14 debian/changelog
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 4:9.1.0-1+stereo3d3+lc1 --toolkit /toolkit
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 || { tail -20 /out/build-dep.log; exit 1; }
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder /out
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x digikam_9.1.0-1+stereo3d3+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || { echo BUILD-FAILED; tail -30 /out/build.log; exit 1; }
cd /out/lc
env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS PYTHONPATH=/toolkit python3 -m lean.release check-link --previous-dir /prev /out/lc/*+lc1_*.deb > /out/check-link.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
