# Sparky Stereo OS, ORDER 247: rebuild of lane 41's mpv-dmo +stereo3d7 as +stereo3d8, same container layout as the other scripts here. Created by Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p /repo && cd /repo && cp /stage/*/*.deb . && dpkg-scanpackages -m . 2>/dev/null > Packages
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/staged.list
printf 'Package: *\nPin: origin ""\nPin-Priority: 1002\n' > /etc/apt/preferences.d/staged
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends install devscripts quilt xz-utils >/dev/null 2>&1
mkdir -p /out/lc && cd /out/lc && cp /in/* .
dpkg-source -x mpv-dmo_0.41.0-dmo9+stereo3d7+lc1.dsc src >/dev/null 2>&1
cd src
python3 - <<'PY'
s=open('debian/changelog').read()
s=s.replace('mpv-dmo (1:0.41.0-dmo9+stereo3d7+lc1) UNRELEASED','mpv-dmo (1:0.41.0-dmo9+stereo3d7) unstable',1)
open('debian/changelog','w').write(s)
r=open('debian/rules').read(); m='# Distribution-only processing; authored source remains in the source archive.'
assert r.count(m)==1; open('debian/rules','w').write(r.split(m)[0].rstrip('\n')+'\n')
PY
rm -rf debian/sparky-lean-toolkit
cp -a player/command.c /tmp/command.c.orig
python3 /patch/mpv8-edit.py
{ printf 'Description: keep the explicit save-to-file command, beside the per-file store\n The published +stereo3d6 command video-stereo-store-swap wrote the swap of the eyes\n into the playing local file (user.stereo-policy.swap-eyes). +stereo3d7 replaced it by\n a second write of the per-file playback state, which removed the way to save the\n correction to the file. The command is back under the same name: it writes the file\n only when asked, then unmarks the per-file mark; the swap property alone keeps its\n choice in the per-file store.\nAuthor: Daniel Campos Ramos <Capitain_Jack@yahoo.com>\nForwarded: no\nLast-Update: 2026-10-24\n\n'; diff -u --label a/player/command.c --label b/player/command.c /tmp/command.c.orig player/command.c || true; } > debian/patches/mpv-store-swap-to-file.patch
echo mpv-store-swap-to-file.patch >> debian/patches/series
cp /tmp/command.c.orig player/command.c
QUILT_PATCHES=debian/patches quilt push -a -q 2>&1 | tail -1 || true
dch --newversion 1:0.41.0-dmo9+stereo3d8 --distribution unstable 'Keep the explicit save-to-file command video-stereo-store-swap, under the name the published +stereo3d6 used: it writes the swap of the eyes into the playing local file only when asked and then unmarks the per-file mark; the swap property keeps the person'"'"'s choice in the per-file store alone. +stereo3d7 had replaced the command by a second per-file-store write, which removed the way to save to the file.'
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 1:0.41.0-dmo9+stereo3d8+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 || { tail -20 /out/build-dep.log; exit 1; }
useradd --create-home --uid 1000 builder 2>/dev/null || true
chown -R builder /out
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x mpv-dmo_0.41.0-dmo9+stereo3d8+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || { echo BUILD-FAILED; tail -30 /out/build.log; }
cd /out/lc && PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
