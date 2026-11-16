#!/bin/bash
# Phase 2 of libstereo-av1.sh, inside a container whose /proc/cpuinfo is a faked processor: apt installs libstereo-av1 from the throwaway
# tree (pinned over the published one, whose version is the same) and the library's hash says which build it is.
set -uo pipefail
sh /run/https-only-apt.sh >/dev/null
cp /apt/62sparky-stereo-variants /etc/apt/apt.conf.d/; install -Dm644 /apt/variants/varianttable /usr/share/sparky-stereo-apt/varianttable
rm -f /etc/apt/sources.list.d/debian.sources
cat >/etc/apt/sources.list.d/debian.sources <<'S'
Types: deb
URIs: https://deb.debian.org/debian
Suites: forky
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
S
printf 'deb [trusted=yes] file:/repo mashtabba main\ndeb [trusted=yes] file:/work/av1/tree mashtabba main\n' >/etc/apt/sources.list.d/sparky.list
apt-get -y update >/dev/null 2>&1 || true
dpkg-deb -x /repo/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_*_all.deb /tmp/dmo
printf 'Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /tmp/dmo/usr/share/keyrings/deb-multimedia-keyring.pgp\n' >/etc/apt/sources.list.d/dmo.sources
printf 'Package: *\nPin: release o=Toy variants\nPin-Priority: 1001\n' >/etc/apt/preferences.d/toy
apt-get -y update >/dev/null 2>&1
apt-get -y install libstereo-av1 >/tmp/install.out 2>&1 || { tail -5 /tmp/install.out; echo "install failed"; exit 1; }
h=$(sha256sum /usr/lib/x86_64-linux-gnu/libstereo-av.so.1.* | head -1 | cut -d' ' -f1)
if [ "$h" = "$(sed -n 's/^v3 //p' /work/av1/hashes)" ]; then echo "installed: v3"; elif [ "$h" = "$(sed -n 's/^base //p' /work/av1/hashes)" ]; then echo "installed: base"; else echo "installed: unknown $h"; fi
