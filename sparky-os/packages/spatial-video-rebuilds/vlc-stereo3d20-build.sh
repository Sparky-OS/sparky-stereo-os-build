# Sparky Stereo OS, ORDER 578: vlc-stereo +stereo3d20, the published +stereo3d19+lc1 source made plain again (repo/plain-from-lc.py), with 3d-0049 (on Wayland the video output draws on a surface of its own, a sub-surface of the main window while the video is shown, so that Qt hiding a window of the interface no longer ends the connection with "invalid object") added as its own patch, built through Lean Code. Runs as root inside a container of the published set (Debian testing, deb-multimedia and the edition's repository pinned at 1001); mounts: /in the +stereo3d19+lc1 source package, /toolkit sparky-os, /prev the +stereo3d19+lc1 .deb files for the link and start gate, /out. Created by Daniel Ramos (Capitain Jack) 2026/11/15
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
P=3d-0049-qt-Wayland-draw-the-video-on-a-surface-of-its-own.patch
apt-get -y --error-on=any update >/dev/null 2>&1 </dev/null
apt-get -y --no-install-recommends install devscripts quilt xz-utils >/dev/null 2>&1 </dev/null
mkdir -p /out/lc && cd /out/lc && cp /in/* .
dpkg-source -x vlc_3.0.24-1+stereo3d19+lc1.dsc src >/dev/null 2>&1
# back to the authored +stereo3d19: the checked inverse of lean.debian_prepare (the toolkit, its six build
# dependencies at the front of Build-Depends, its changelog entry and its rules targets; this source has no preserve plan)
python3 /toolkit/repo/plain-from-lc.py src
cd src
cp /toolkit/upstream/vlc/${P#3d-} debian/patches/$P
echo $P >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a
dch --date "$SOURCE_DATE_RFC2822" --newversion 3.0.24-1+stereo3d20 --distribution unstable 'On Wayland the video is drawn on a surface of its own (3d-0049): VLC closed with "wl_display#1: error 0: invalid object N" (or "wp_viewport#N: error 3: the wl_surface for this viewport no longer exists") when a window of the interface was hidden while a video played, for example when Ctrl+L or the playlist button moved the playing video into the playlist, because the video was drawn on the surface of a Qt window and Qt 5 destroys a hidden window'"'"'s surface. The surface is now made by the interface for the video output, as VLC 4 does, and is a sub-surface of the main window while the video is shown; the widget that holds its place takes the mouse and the keys, as on X11. The video stays one declared full side by side surface in 3D.'
head -14 debian/changelog
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 3.0.24-1+stereo3d20+lc1 --toolkit /toolkit
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 </dev/null || { tail -20 /out/build-dep.log; exit 1; }
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root, against the archives of sources.json
: "${SPARKY_LC_ARCHIVE_CONFIG:?the signed archive configuration of the link gate (sparky-os/lean/archive.md)}"
: "${SPARKY_LC_SCRATCH:?the scratch directory of the link gate}"
apt-get -y --no-install-recommends install bubblewrap >> /out/build-dep.log 2>&1 </dev/null
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder 2>/dev/null || true
chown -R builder /out
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" /out/lc/src
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x vlc_3.0.24-1+stereo3d20+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
rc=0
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || rc=$?
echo "dpkg-buildpackage exit $rc" >> /out/build.log
[ "$rc" = 0 ] || { echo BUILD-FAILED; tail -30 /out/build.log; chown -R 1000:1000 /out; exit "$rc"; }
cd /out/lc && PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
