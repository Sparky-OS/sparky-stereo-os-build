#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 1000
cd /mnt/build/gl-stereo/proof-rootfs
tar --exclude='./dev' --exclude='./proc' --exclude='./sys' --exclude='./run' \
    --exclude='./home/stereo-test' \
    --exclude='./build' --exclude='./workspace' --exclude='./var/local/sparky-stereo-repo' \
    --owner=0 --group=0 --numeric-owner -cf /mnt/build/gl-stereo/proof-rootfs.tar .
tar --owner=1000 --group=1000 --numeric-owner -rf /mnt/build/gl-stereo/proof-rootfs.tar ./home/stereo-test
