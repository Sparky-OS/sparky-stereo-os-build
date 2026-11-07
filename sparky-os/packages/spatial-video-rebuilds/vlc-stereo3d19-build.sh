# Sparky Stereo OS, ORDER 265c: vlc-stereo +stereo3d19, the published +stereo3d16+lc1 source with 3d-0047 (the 3D video of an X11 window drawn on a window of the video output's own that holds the views at their resolution and is declared to Stereo KWin, the declaration removed when the video closes, the notices when the desktop does not take it, on X11 and on Wayland) and 3d-0048 (the notices in the languages of the edition) added as their own patches, built through Lean Code. Runs as root inside a container of the published set (Debian testing, deb-multimedia and the edition's repository pinned at 1001); mounts: /in the +stereo3d16+lc1 source package, /toolkit sparky-os, /prev the +stereo3d16+lc1 .deb files for the link and start gate, /out. Created by Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
REPRO=/toolkit/repo/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): the container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); a missing helper stops the script
sh /run/https-only-apt.sh || exit 1
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
P1=3d-0047-opengl-3D-video-of-an-X11-window-in-3D-at-its-own-resolution.patch
P2=3d-0048-po-the-3D-flat-and-reduced-notices-in-the-languages-.patch
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends install devscripts quilt xz-utils >/dev/null 2>&1
mkdir -p /out/lc && cd /out/lc && cp /in/* .
dpkg-source -x vlc_3.0.24-1+stereo3d16+lc1.dsc src >/dev/null 2>&1
cd src
# back to the authored +stereo3d16: the Lean Code stage out of debian/rules and its toolkit out of debian/, its build
# dependencies once out of the front of Build-Depends (each preparation adds them again), and the published +lc1 entry
# marked released, so that dch opens a new entry instead of renaming it; then libstereo-declare 1.7.0, the first with
# stereo_declare_x11_child, as the version the video output needs
python3 - <<'PY'
s=open('debian/changelog').read(); old='vlc (3.0.24-1+stereo3d16+lc1) UNRELEASED;'
assert s.startswith(old); open('debian/changelog','w').write(s.replace(old,'vlc (3.0.24-1+stereo3d16+lc1) unstable;',1))
r=open('debian/rules').read(); m='# Distribution-only processing; authored source remains in the source archive.'
assert r.count(m)==1; open('debian/rules','w').write(r.split(m)[0].rstrip('\n')+'\n')
c=open('debian/control').read(); lc='Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml, '
assert c.count(lc)==1; c=c.replace(lc,'Build-Depends: ',1)
a=' libstereo-declare-dev,\n'; assert c.count(a)==1; c=c.replace(a,' libstereo-declare-dev (>= 1.7.0),\n',1)
b='Depends: libmedia-gpu-route0 (>= 0.1.0+lc1), '; assert c.count(b)==1; c=c.replace(b,'Depends: libstereo-declare1 (>= 1.7.0), libmedia-gpu-route0 (>= 0.1.0+lc1), ',1)
open('debian/control','w').write(c)
PY
rm -rf debian/sparky-lean-toolkit
for P in $P1 $P2; do
  cp /toolkit/upstream/vlc/${P#3d-} debian/patches/$P
  echo $P >> debian/patches/series
done
QUILT_PATCHES=debian/patches quilt push -a
dch --date "$SOURCE_DATE_RFC2822" --newversion 3.0.24-1+stereo3d19 --distribution unstable '3D video shows in 3D on X11, each view at its own resolution (3d-0047): the video output draws a 3D video on a window of its own inside the interface'"'"'s video window, holding the two views at the resolution they have, declared to Stereo KWin as a stereo child of the interface window with the size one view is shown at (libstereo-declare 1.7.0, support version 8), so that Stereo KWin resizes each view once; the declaration is removed when the video closes. Where the desktop announces less than 8, each view is drawn at half the width of the video window and VLC says so; where it takes no declaration, or the declaration fails, VLC says so in its messages and in a dialog, on X11 and on Wayland, instead of showing the 3D video flat as if it worked. Each dialog shows once per VLC session, each kind once (Daniel, 2026-11-07: "once per session"); the log says it for every video. The notices are in the nine languages (3d-0048), the Korean and Polish reduced-width strings as reviewed in ORDER 440.'
head -12 debian/changelog
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 3.0.24-1+stereo3d19+lc1 --toolkit /toolkit
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 || { tail -20 /out/build-dep.log; exit 1; }
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root, against the archives of sources.json
: "${SPARKY_LC_ARCHIVE_CONFIG:?the signed archive configuration of the link gate (sparky-os/lean/archive.md)}"
: "${SPARKY_LC_SCRATCH:?the scratch directory of the link gate}"
apt-get -y --no-install-recommends install bubblewrap >> /out/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder 2>/dev/null || true
chown -R builder /out
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" /out/lc/src
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x vlc_3.0.24-1+stereo3d19+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || { echo BUILD-FAILED; tail -30 /out/build.log; }
cd /out/lc && PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
