#!/bin/bash
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
# Mount the candidate at /copy, its matching live baseline at /baseline,
# the release toolkit at /toolkit, and owned output at /w.
set -euo pipefail
test -f /.dockerenv
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export DEBIAN_FRONTEND=noninteractive
trap 'chown -R 1000:1000 /w' EXIT
if ! command -v rsync >/dev/null; then
 mkdir /tmp/order223-apt-sources
 mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources /tmp/order223-apt-sources/ 2>/dev/null || true
 printf 'deb http://deb.debian.org/debian testing main\n' > /etc/apt/sources.list
 apt-get -y update > /w/rsync-apt-update.log 2>&1
 apt-get -y --no-install-recommends install rsync > /w/rsync-apt-install.log 2>&1
fi
mkdir -m 700 /tmp/order223-verify-key
gpg --no-options --homedir /tmp/order223-verify-key --batch --dearmor --output /w/proof-public.gpg /copy/sparky-stereo-repo.asc
{
 gpgv --homedir /tmp/order223-verify-key --keyring /w/proof-public.gpg /copy/dists/mashtabba/InRelease
 gpgv --homedir /tmp/order223-verify-key --keyring /w/proof-public.gpg /copy/dists/mashtabba/Release.gpg /copy/dists/mashtabba/Release
 gpg --no-options --homedir /tmp/order223-verify-key --no-default-keyring --keyring /w/proof-public.gpg --batch --decrypt /copy/dists/mashtabba/InRelease | cmp - /copy/dists/mashtabba/Release
 echo 'Both signatures accepted and the signed body equals Release'
} > /w/candidate-signatures.log 2>&1
export SPARKY_STEREO_CONFIG=/dev/null SPARKY_SYNC_TARGET=/baseline
# This runs the release check-repo gate, then only rsync --dry-run operations.
# The target is the exact local live snapshot, never an SSH endpoint.
bash /toolkit/repo/sync-to-server.sh /copy > /w/sync-dry-run.log 2>&1
