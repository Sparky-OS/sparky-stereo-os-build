#!/bin/bash
# The variant written at BUILD time (ORDER 108): inside a container (root, network for Debian and deb-multimedia), libstereo-av1 of the published
# stereo-layer built for x86-64-v3 with debian/rules untouched. The recipe's one step on the source is XB-Architecture-Variant in each binary stanza of
# debian/control, which dpkg-gencontrol copies into every binary control file; -march=x86-64-v3 goes in through DEB_CFLAGS_MAINT_APPEND and
# DEB_CXXFLAGS_MAINT_APPEND. The link and start gate runs with the toolkit that leaves Architecture-Variant out of its local index (lean/archive.py);
# the source package carries an older copy of the toolkit (debian/sparky-lean-toolkit), so this step puts the fixed archive.py and package.py (the
# -lc-hr companion of a variant carries the variant too) in it, as a toolkit release will.
# Mounts: /sl (stereo-layer_1.18.0-1+lc1.dsc and its tarballs), /repo (the published tree), /keys (debian.pgp, dmo.pgp, sparky.gpg),
# /toolkit (sparky-os of the build tree, for lean/archive.py), /work (output: out/*.deb).
set -euo pipefail
sh /run/https-only-apt.sh >/dev/null
export DEBIAN_FRONTEND=noninteractive HOME=/tmp
echo "deb [trusted=yes] file:/repo mashtabba main" >/etc/apt/sources.list.d/sparky.list
printf "Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /keys/dmo.pgp\n" >/etc/apt/sources.list.d/dmo.sources
apt-get -y update >/dev/null 2>&1
apt-get -y install ca-certificates dpkg-dev devscripts equivs bubblewrap gnupg binutils >/dev/null 2>&1
mkdir -p /work/lcscratch
cat >/work/archives.json <<'JSON'
[{"uri":"https://deb.debian.org/debian","suite":"forky","components":["main"],"keyring":"/keys/debian.pgp"},
 {"uri":"https://www.deb-multimedia.org","suite":"forky","components":["main","non-free"],"keyring":"/keys/dmo.pgp"},
 {"uri":"file:/repo","suite":"mashtabba","components":["main"],"keyring":"/keys/sparky.gpg"}]
JSON
export SPARKY_LC_ARCHIVE_CONFIG=/work/archives.json SPARKY_LC_SCRATCH=/work/lcscratch
cd /work; dpkg-source -x /sl/stereo-layer_1.18.0-1+lc1.dsc src >/dev/null 2>&1
cd src
awk '/^Package: / {print; print "XB-Architecture-Variant: amd64v3"; next} {print}' debian/control >debian/control.new && mv debian/control.new debian/control
cp /toolkit/lean/archive.py /toolkit/lean/package.py debian/sparky-lean-toolkit/lean/
export DEB_BUILD_PROFILES=pkg.stereo-layer.av DEB_BUILD_OPTIONS=parallel=2
mk-build-deps -r -i -t "apt-get -y --no-install-recommends" debian/control >/work/builddeps.log 2>&1 || { tail -5 /work/builddeps.log; exit 1; }
export DEB_CFLAGS_MAINT_APPEND="-march=x86-64-v3" DEB_CXXFLAGS_MAINT_APPEND="-march=x86-64-v3"
{ dpkg-buildpackage -B -us -uc -d -Ppkg.stereo-layer.av >/work/build-v3.log 2>&1; echo "v3 build exit=$?"; } || true
mkdir -p /work/out; mv /work/*.deb /work/out/ 2>/dev/null || true
for d in /work/out/*.deb; do printf '%s: Architecture-Variant=%s\n' "$(basename "$d")" "$(dpkg-deb -f "$d" Architecture-Variant)"; done
