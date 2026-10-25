# Sparky Stereo OS, ORDER 249: vlc-stereo +stereo3d16, the published +stereo3d15+lc1 source with 3d-0046 (full screen on Wayland as on X11) added as its own patch, built through Lean Code. Runs as root inside a container of the published set (Debian testing, deb-multimedia and the edition's repository pinned at 1001); mounts: /in the +stereo3d15+lc1 source package, /toolkit sparky-os, /prev the +stereo3d15+lc1 .deb files for the link and start gate, /out. Created by Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
P=3d-0046-qt-full-screen-on-Wayland-as-on-X11-one-double-click.patch
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends install devscripts quilt xz-utils >/dev/null 2>&1
mkdir -p /out/lc && cd /out/lc && cp /in/* .
dpkg-source -x vlc_3.0.24-1+stereo3d15+lc1.dsc src >/dev/null 2>&1
cd src
# back to the authored +stereo3d15: the Lean Code stage out of debian/rules and its toolkit out of debian/, its build
# dependencies once out of the front of Build-Depends (each preparation adds them again), and the published +lc1 entry
# marked released, so that dch opens a new entry instead of renaming it
python3 - <<'PY'
s=open('debian/changelog').read(); old='vlc (3.0.24-1+stereo3d15+lc1) UNRELEASED;'
assert s.startswith(old); open('debian/changelog','w').write(s.replace(old,'vlc (3.0.24-1+stereo3d15+lc1) unstable;',1))
r=open('debian/rules').read(); m='# Distribution-only processing; authored source remains in the source archive.'
assert r.count(m)==1; open('debian/rules','w').write(r.split(m)[0].rstrip('\n')+'\n')
c=open('debian/control').read(); lc='Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml, '
assert c.count(lc)==1; open('debian/control','w').write(c.replace(lc,'Build-Depends: ',1))
PY
rm -rf debian/sparky-lean-toolkit
cp /toolkit/upstream/vlc/${P#3d-} debian/patches/$P
echo $P >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push
dch --newversion 3.0.24-1+stereo3d16 --distribution unstable 'Full screen on Wayland behaves as on X11 (3d-0046): a double click enters and leaves VLC'"'"'s full screen as F does, with the menu bar and the controls hidden (Qt'"'"'s press of the double click no longer counts as a second one); moving the mouse shows the full screen controller at the bottom of the screen (a popup of the main window, where KWin centred a tool window on the video) and the cursor, both hidden again after mouse-hide-timeout; the controller stays while the pointer is over it and keeps its cursor.'
head -12 debian/changelog
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 3.0.24-1+stereo3d16+lc1 --toolkit /toolkit
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 || { tail -20 /out/build-dep.log; exit 1; }
useradd --create-home --uid 1000 builder 2>/dev/null || true
chown -R builder /out
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x vlc_3.0.24-1+stereo3d16+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || { echo BUILD-FAILED; tail -30 /out/build.log; }
cd /out/lc && PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
