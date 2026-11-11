#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/08
# Copyright 2026 under the GNU GPL3 License
# ORDER 462: the call the FFmpeg source makes at override_dh_builddeb (lean.release check-link, from debian/rules through
# lean.debhelper), reached here with a small package instead of a three-hour FFmpeg build. Inside a Debian testing container
# with python3, apt and the build repository at /repo (read only); network for apt only.
#   RED     the environment the old helper gave dpkg-buildpackage (nothing): the station's message, word for word
#   GREEN   the environment this helper gives it: link-config's archive.json and a private scratch; the gate no longer stops
#           at that message (what it does next is the gate's own work, shown)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FDKLIB=$HERE/../lib
T=$(mktemp -d)
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
FAILS=0
mkdir -p "$T/pkg/DEBIAN" "$T/lc" && printf 'Package: sparky-tiny\nVersion: 1\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: a package the link gate can read\n' >"$T/pkg/DEBIAN/control"
dpkg-deb -b "$T/pkg" "$T/sparky-tiny_1_all.deb" >/dev/null
export PYTHONPATH=/repo/sparky-os
echo "=== RED: no archives configured (what the old helper's build had)"
env -u SPARKY_LC_ARCHIVE_CONFIG -u SPARKY_LC_SCRATCH python3 -m lean.release check-link "$T/sparky-tiny_1_all.deb" >"$T/red.log" 2>&1
red=$?
cat "$T/red.log" | tail -2
ok "the gate stops with the station's message and a failing status" '[ $red -ne 0 ] && grep -q "check-link needs --archive-config / --scratch (or SPARKY_LC_ARCHIVE_CONFIG / SPARKY_LC_SCRATCH)" "$T/red.log"'
ok "the helper names that cause (LOCAL85), not a generic failure" '. "$FDKLIB/common.sh"; [ "$(explain_build_failure "$T/red.log" | cut -d" " -f1)" = LOCAL85 ]'
echo "=== GREEN: the archives this computer's own apt sources give (link-config)"
python3 "$FDKLIB/link-config" "$T/lc" dash >"$T/lc.out" 2>&1; lcrc=$?
cat "$T/lc.out" | head -3
ok "link-config writes archive.json from the container's apt sources" '[ $lcrc -eq 0 ] && [ -s "$T/lc/archive.json" ]'
mkdir -p "$T/lc/scratch"
SPARKY_LC_ARCHIVE_CONFIG=$T/lc/archive.json SPARKY_LC_SCRATCH=$T/lc/scratch python3 -m lean.release check-link "$T/sparky-tiny_1_all.deb" >"$T/green.log" 2>&1
green=$?
tail -4 "$T/green.log"
ok "the gate gets past its configuration check" '! grep -q "check-link needs --archive-config" "$T/green.log"'
echo "gate exit status with the archives configured: $green (0 = qualified)"
echo "SUMMARY: $FAILS failing"
[ "$FAILS" = 0 ]
