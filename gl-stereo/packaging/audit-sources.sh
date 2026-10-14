#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
repo=$PWD
apt_dir=$repo/out/packages/apt
mkdir -p "$apt_dir/keyring"
dpkg-deb -x /var/local/sparky-stereo-repo/carried/deb-multimedia-keyring_2024.9.1_all.deb "$apt_dir/keyring"
cat > "$apt_dir/sources.list" <<'SOURCES'
deb http://deb.debian.org/debian testing main
deb-src http://deb.debian.org/debian testing main
deb [trusted=yes] file:///var/local/sparky-stereo-repo ./
SOURCES
printf 'deb [signed-by=%s/keyring/usr/share/keyrings/deb-multimedia-keyring.pgp] http://www.deb-multimedia.org forky main\n' "$apt_dir" >> "$apt_dir/sources.list"
args=(-o "Dir::State::lists=$apt_dir/lists" -o "Dir::Cache=$apt_dir/cache"
      -o "Dir::Etc::sourcelist=$apt_dir/sources.list" -o Dir::Etc::sourceparts=-
      -o APT::Sandbox::User= -o Debug::NoLocking=1)
export DEBIAN_FRONTEND=noninteractive
apt-get "${args[@]}" -y update
for package in kscreenlocker plasma-desktop xscreensaver; do
    apt-cache "${args[@]}" showsrc "$package" > "out/packages/$package.source"
    apt-get "${args[@]}" -y --simulate build-dep "$package" > "out/packages/$package.build-deps" 2>&1 || true
done
apt-get "${args[@]}" -y --simulate build-dep kscreenlocker plasma-desktop xscreensaver >out/packages/combined.build-deps
mapfile -t selected < <(awk '/^Inst / {print $2 "=" substr($3,2)}' out/packages/combined.build-deps)
apt-cache "${args[@]}" show "${selected[@]}" >out/packages/selected.metadata
awk '/^Installed-Size:/ {installed += $2 * 1024} /^Size:/ {download += $2}
     END {printf "Installed dependency bytes: %.0f\nDownload bytes: %.0f\n", installed, download}' \
    out/packages/selected.metadata >out/packages/size-estimate.txt
apt-cache "${args[@]}" policy libstereo-declare-dev qt6-base-dev libkf6config-dev >out/packages/versions.txt
cd out/packages/sources
apt-get "${args[@]}" -y source --download-only kscreenlocker plasma-desktop xscreensaver
