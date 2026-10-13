#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" != 0
repo=$PWD
mkdir -p out/plasma/apt/lists/partial out/plasma/apt/cache out/plasma/debs out/plasma/sdk
printf '%s\n' 'deb http://deb.debian.org/debian testing main' >out/plasma/apt/sources.list
options=(-o "Dir::State::lists=$repo/out/plasma/apt/lists" -o "Dir::Cache=$repo/out/plasma/apt/cache" -o "Dir::Etc::sourcelist=$repo/out/plasma/apt/sources.list" -o Dir::Etc::sourceparts=- -o Debug::NoLocking=1)
apt-get "${options[@]}" update
cd out/plasma/debs
apt-get "${options[@]}" download "$@"
for deb in *.deb; do dpkg-deb -x "$deb" "$repo/out/plasma/sdk"; done
