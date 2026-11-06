#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/06
# Builds a package for the tests from build.sh itself, without the two steps that need the edition's machinery (the
# engine's message catalogs and Lean Code's sealing): run in a throwaway container with dpkg-deb. The package is the same
# files, scripts and triggers as the published one, and its control without the engine in Depends (the tests stub the
# engine's Python module).
#   make-test-deb.sh OUTDIR
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(readlink -f "${1:?output folder}")
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
sed -e '/^sparky-stereo-problems catalog /d' \
	-e 's|^PYTHONPATH=.*--authoring "\$HERE"$|dpkg-deb --root-owner-group --build "$D" "$OUT/${PKG}_${VERSION}_all.deb" >/dev/null|' \
	-e 's|^find "\$D/usr/lib/systemd".*$||' \
	-e 's|^Depends: python3, gettext, dpkg, sparky-stereo-problems (>= 0.1.0)$|Depends: python3, gettext, dpkg|' "$HERE/../build.sh" >"$W/build.sh"
grep -q 'dpkg-deb --root-owner-group' "$W/build.sh"
cp -r "$HERE/.." "$W/pkg"
mv "$W/build.sh" "$W/pkg/build.sh"
OUT=$OUT bash "$W/pkg/build.sh"
