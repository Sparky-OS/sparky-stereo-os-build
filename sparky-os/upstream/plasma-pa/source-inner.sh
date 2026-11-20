#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ulimit -c 1
trap 'chown -R "$BUILD_UID:$BUILD_GID" /work' EXIT
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
apt-get update --error-on=any
apt-get -y --no-install-recommends install build-essential dpkg-dev devscripts debhelper quilt fakeroot gettext python3 python3-yaml nodejs node-acorn ca-certificates
python3 /build-tree/sparky-os/upstream/plasma-pa/make-source.py /source-input/plasma-pa_6.7.4-1.dsc /work/prepared
