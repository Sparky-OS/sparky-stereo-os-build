#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 1000
build=/mnt/build/gl-stereo
root=$build/proof-rootfs
mkdir "$root"
tar --no-same-owner --exclude=dev --exclude=proc --exclude=sys -xf "$build/base.tar" -C "$root"
mkdir -p "$root"/{dev,proc,sys,tmp,var/local/sparky-stereo-repo,build}
printf '#!/bin/sh\nexit 101\n' >"$root/usr/sbin/policy-rc.d"
chmod +x "$root/usr/sbin/policy-rc.d"
printf '%s\n' 'deb http://deb.debian.org/debian testing main' 'deb [trusted=yes] file:///var/local/sparky-stereo-repo ./' >"$root/etc/apt/sources.list"
rm "$root/etc/apt/sources.list.d/debian.sources"
cp /etc/resolv.conf "$root/etc/resolv.conf"
printf 'APT::Sandbox::User "root";\n' >"$root/etc/apt/apt.conf.d/99-rootless"
