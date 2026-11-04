#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 1000
build=/mnt/build/gl-stereo
apt_dir=$build/bootstrap
mkdir -p "$apt_dir/lists/partial" "$apt_dir/cache/archives/partial" "$apt_dir/tools"
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): this container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); not root, so its settings go to a file apt is pointed at
HTTPS_ONLY_APT_CONF=$apt_dir/https-only-apt.conf sh /run/https-only-apt.sh
export APT_CONFIG=$apt_dir/https-only-apt.conf
echo 'deb https://deb.debian.org/debian testing main' >"$apt_dir/sources.list"
args=(-o "Dir::State::lists=$apt_dir/lists" -o "Dir::Cache=$apt_dir/cache" -o "Dir::Etc::sourcelist=$apt_dir/sources.list" -o Dir::Etc::sourceparts=- -o APT::Sandbox::User= -o Debug::NoLocking=1)
export DEBIAN_FRONTEND=noninteractive
apt-get "${args[@]}" -y update
cd "$apt_dir/tools"
apt-get "${args[@]}" -y download proot libtalloc2
for deb in *.deb; do dpkg-deb -x "$deb" "$apt_dir/tools"; done
cd "$build/rootfs"
tar --no-same-owner --exclude=dev --exclude=proc --exclude=sys -xf "$build/base.tar"
mkdir -p dev proc sys tmp var/local/sparky-stereo-repo build
printf '#!/bin/sh\nexit 101\n' >usr/sbin/policy-rc.d
chmod +x usr/sbin/policy-rc.d
printf '%s\n' 'deb https://deb.debian.org/debian testing main' 'deb-src https://deb.debian.org/debian testing main' 'deb [trusted=yes] file:///var/local/sparky-stereo-repo ./' >etc/apt/sources.list
rm -f etc/apt/sources.list.d/debian.sources
cp /etc/resolv.conf etc/resolv.conf
printf 'APT::Sandbox::User "root";\n' >etc/apt/apt.conf.d/99-rootless
