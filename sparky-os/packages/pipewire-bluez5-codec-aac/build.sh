#!/bin/sh
# PipeWire's Bluetooth AAC codec plugin, which Debian leaves out (fdk-aac is non-free).
# Built from the upstream tag of the PipeWire version installed, in a throwaway Debian
# testing container; packaged as pipewire-bluez5-codec-aac for that exact version.
# Usage: build.sh [pipewire upstream version] [debian version it pairs with]
set -e
PWV=${1:-1.6.8}
DEBV=${2:-1.6.8-1}
OUT=${OUT:-/K3D/temp/bt-aac}
mkdir -p "$OUT"
docker run --rm -v "$OUT:/out" -e PWV="$PWV" -e DEBV="$DEBV" -e HOSTID="$(id -u):$(id -g)" debian:testing sh -ec '
  sed -i "s/^Types: deb$/Types: deb deb-src/; s/^Components: main$/Components: main non-free/" /etc/apt/sources.list.d/debian.sources
  apt-get -q update >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get -q -y build-dep pipewire >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get -q -y install git libfdk-aac-dev >/dev/null
  git clone -q --depth 1 -b "$PWV" https://gitlab.freedesktop.org/pipewire/pipewire.git /src
  cd /src
  meson setup build -Dauto_features=disabled -Dbluez5=enabled -Dbluez5-codec-aac=enabled \
    -Dsession-managers=[] -Dexamples=disabled -Dtests=disabled -Ddbus=enabled >/out/meson.log 2>&1 \
    || { tail -30 /out/meson.log; exit 1; }
  ninja -C build spa/plugins/bluez5/libspa-codec-bluez5-aac.so >/out/ninja.log 2>&1 || { tail -30 /out/ninja.log; exit 1; }
  so=build/spa/plugins/bluez5/libspa-codec-bluez5-aac.so
  strip --strip-unneeded "$so"
  P=/pkg; D=$P/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5
  mkdir -p $D $P/DEBIAN $P/usr/share/doc/pipewire-bluez5-codec-aac
  cp "$so" $D/
  cp COPYING $P/usr/share/doc/pipewire-bluez5-codec-aac/copyright
  cat >$P/DEBIAN/control <<CTL
Package: pipewire-bluez5-codec-aac
Version: $DEBV+aac1
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Depends: libspa-0.2-bluetooth (= $DEBV), libfdk-aac2 (>= 2.0.0)
Section: non-free/sound
Priority: optional
Homepage: https://sparkylinux.org
Description: PipeWire Bluetooth AAC codec (A2DP)
 The AAC codec plugin of PipeWire $PWV, which Debian builds without because
 fdk-aac is non-free. Headsets that offer AAC (most earbuds and many
 headphones) then play AAC instead of SBC. Built from the upstream tag of the
 PipeWire version it pairs with; rebuild it when PipeWire is upgraded.
CTL
  dpkg-deb --root-owner-group -b $P /out/pipewire-bluez5-codec-aac_${DEBV}+aac1_amd64.deb >/dev/null
  ldd $D/libspa-codec-bluez5-aac.so | grep -E "fdk|not found"
  chown "$HOSTID" /out/pipewire-bluez5-codec-aac_${DEBV}+aac1_amd64.deb
'
ls -la "$OUT"/*.deb
