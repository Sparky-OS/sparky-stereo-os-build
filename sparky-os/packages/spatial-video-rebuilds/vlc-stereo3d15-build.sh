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
dpkg-source -x vlc_3.0.24-1+stereo3d14+lc1.dsc src >/dev/null 2>&1
cd src
python3 - <<'PY'
s=open('debian/changelog').read()
s=s.replace('vlc (3.0.24-1+stereo3d14+lc1) UNRELEASED','vlc (3.0.24-1+stereo3d14) unstable',1)
open('debian/changelog','w').write(s)
r=open('debian/rules').read(); m='# Distribution-only processing; authored source remains in the source archive.'
assert r.count(m)==1; open('debian/rules','w').write(r.split(m)[0].rstrip('\n')+'\n')
c=open('debian/control').read(); assert ' liblua5.4-dev,\n' in c
c=c.replace(' liblua5.4-dev,\n',' liblua5.4-dev,\n libgme-dev,\n libvpl-dev,\n',1); assert 'Standards-Version:' in c; c=c.replace('Standards-Version:','Build-Conflicts: liblua5.2-dev\nStandards-Version:',1); open('debian/control','w').write(c)
PY
head -12 debian/changelog
rm -rf debian/sparky-lean-toolkit
dch --newversion 3.0.24-1+stereo3d15 --distribution unstable 'Rebuild with libgme-dev and libvpl-dev named in Build-Depends: +stereo3d14 was built where they were not installed and silently lost the QSV and game-music plugins (libqsv_plugin.so, libgme_plugin.so); the Lua plugin linked Lua 5.2 because liblua5.2-dev was installed, so Build-Conflicts: liblua5.2-dev makes it Lua 5.4 again, as in +stereo3d13.'
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . 3.0.24-1+stereo3d15+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 || { tail -20 /out/build-dep.log; exit 1; }
dpkg -l | grep -E "liblua5|libgme|libvpl" | awk '{print $2,$3}'
useradd --create-home --uid 1000 builder 2>/dev/null || true
chown -R builder /out
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x vlc_3.0.24-1+stereo3d15+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || { echo BUILD-FAILED; tail -30 /out/build.log; }
cd /out/lc && PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
