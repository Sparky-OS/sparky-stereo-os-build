#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later
# The Lean Code release gates on the ORDER 234 cohort, each with a control
# that must fail: check-debs on a copy of libmedia-gpu-route0 with one payload
# byte flipped, and check-link of the new mpv where only the published
# libmedia-gpu-route0 0.1.0 is installed (media_gpu_route_copy_back missing).
# Run with PYTHONPATH set to the release toolkit (sparky-os), in a container
# where the cohort's runtime dependencies are installed.
# Usage: release-gates.sh NEWDIR PREVIOUSDIR WORKDIR
set -u
new=$1 previous=$2 work=$3
rm -rf "$work/tamper" && mkdir -p "$work/tamper"
deb=$(ls "$new"/libmedia-gpu-route0_*_amd64.deb | tail -n 1)
dpkg-deb -R "$deb" "$work/tamper/root"
lib=$(ls "$work"/tamper/root/usr/lib/*/libmedia-gpu-route.so.0.*.*)
python3 - "$lib" <<'FLIP'
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
offset = next(i for i in range(len(data) - 1, 0, -1) if data[i])
data[offset] ^= 0xff
path.write_bytes(bytes(data))
print('flipped byte', offset, 'of', path.name)
FLIP
dpkg-deb -b "$work/tamper/root" "$work/tamper/$(basename "$deb")" >/dev/null 2>&1
echo "== control: check-debs on the flipped payload (must fail)"
python3 -m lean.release check-debs "$work/tamper/$(basename "$deb")"; tampered=$?
echo "== check-debs on the cohort (must pass)"
python3 -m lean.release check-debs "$new"/*.deb; debs=$?
echo "== check-link of mpv and libmpv2 with libmedia-gpu-route0 $(dpkg-query -W -f='${Version}' libmedia-gpu-route0) installed"
python3 -m lean.release check-link --previous-dir "$previous" "$new"/mpv_*_amd64.deb "$new"/libmpv2_*_amd64.deb; link=$?
echo "tampered=$tampered debs=$debs link=$link"
