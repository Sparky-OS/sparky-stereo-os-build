#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Builds the edition's meta-packages from sparky-os/lists/*.list and lists/roles.tsv (lists/make-meta.py
# writes the control files and names the packages): sparky-stereo, sparky-stereo-desktop,
# sparky-stereo-hardware-support, sparky-stereo-languages, sparky-stereo-system, the role tasks
# task-sparky-stereo-<role> and task-sparky-<role>, sparky-stereo-tasks (tasksel) and the
# transitional sparky-stereo-gaming.
# The kernel pair linux-image-sparky-stereo and linux-headers-sparky-stereo is versioned after
# the kernel in the repository (rebuild after a kernel bump). Each is a control file and a copyright file. Version: the build date.
# Last update 2026/10/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
VERSION=${VERSION:-$(date +%Y%m%d)}   # second build of a day: VERSION=YYYYMMDD.1
BUILD_ROOT=${BUILD_ROOT:-/K3D/temp/sparky-os}
mkdir -p "$BUILD_ROOT"
W=$(mktemp -d "$BUILD_ROOT/meta-build.XXXXXX")
trap 'rm -rf "$W"' EXIT

PKGS=$(python3 "$HERE/../../lists/make-meta.py" --list)
if [ -n "${PACKAGES:-}" ]; then
	for PKG in $PACKAGES; do
		case " $PKGS " in *" $PKG "*) ;; *) echo "Unknown task package: $PKG" >&2; exit 2 ;; esac
	done
	PKGS=$PACKAGES
fi
python3 "$HERE/../../lists/make-meta.py" "$VERSION" "$W"
mkdir -p "$OUT"
for PKG in $PKGS; do
	(cd "$W/$PKG" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
	V=$(sed -n 's/^Version: //p' "$W/$PKG/DEBIAN/control")
	printf 'Source: sparky-stereo-meta (%s)\n' "$VERSION" >> "$W/$PKG/DEBIAN/control"
	bash "$HERE/../../repo/provenance.sh" --tree "$W/$PKG"
	mkdir -p "$W/source-trees"
	cp -a "$W/$PKG" "$W/source-trees/"
	PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$W/$PKG" "$OUT"
	echo "built $OUT/${PKG}_${V}_all.deb"
done
python3 "$HERE/build-source.py" "$W/source-trees" "$VERSION" "$OUT"
