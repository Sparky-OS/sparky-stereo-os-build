#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20. Copyright 2026 under the GNU GPL3 License.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
mkdir -p /work/inputs
cp /src/*.dsc /src/*.tar.* /work/inputs/
chown -R 1000:1000 /work
setpriv --reuid=1000 --regid=1000 --clear-groups bash -c '
 export HOME=/tmp/c772-build-home XDG_RUNTIME_DIR=/tmp/c772-build-runtime
 mkdir -p "$HOME" "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
 dbus-run-session -- python3 /machinery/tools/publication-reconcile/rebuild-native.py /work/inputs/kde-spectacle_6.7.4-1+stereo3d3+lc1.dsc /work --new-source-build
 PYTHONPATH=/machinery/sparky-os python3 -m lean.release check-debs /work/*.deb
'
