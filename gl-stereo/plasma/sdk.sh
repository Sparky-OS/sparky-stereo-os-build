#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" != 0
repo=$PWD
mkdir -p out/plasma/apt/lists/partial out/plasma/apt/cache out/plasma/debs out/plasma/sdk
printf '%s\n' 'deb https://deb.debian.org/debian testing main' >out/plasma/apt/sources.list
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): this container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); not root, so its settings go to a file apt is pointed at
HTTPS_ONLY_APT_CONF=$repo/out/plasma/apt/https-only-apt.conf sh /run/https-only-apt.sh
export APT_CONFIG=$repo/out/plasma/apt/https-only-apt.conf
options=(-o "Dir::State::lists=$repo/out/plasma/apt/lists" -o "Dir::Cache=$repo/out/plasma/apt/cache" -o "Dir::Etc::sourcelist=$repo/out/plasma/apt/sources.list" -o Dir::Etc::sourceparts=- -o Debug::NoLocking=1)
apt-get "${options[@]}" update
cd out/plasma/debs
apt-get "${options[@]}" download "$@"
for deb in *.deb; do dpkg-deb -x "$deb" "$repo/out/plasma/sdk"; done
