#!/bin/bash
# Sparky Stereo OS, queue row 50 step 4: the upstream source of OpenSCAD 2026.11-RC1 as openscad_2026.11~rc1.orig.tar.xz.
#   prepare-source.sh OUTDIR [UPSTREAM_CLONE]
# The tag openscad-2026.11-RC1 has no release tarball (upstream published one for RC0 only, on 2026-11-07), so the orig
# tarball is made from the tag's commit, checked against the commit recorded here, with the two submodules the build
# takes from source at the commits the tag pins: Manifold (Debian has no package) and sanitizers-cmake (CMake modules
# read at configuration). The bundled Clipper2, OpenCSG and mimalloc are left out: Debian's are linked.
# VERSION.txt and COMMIT.txt are written as upstream's cmake/Modules/openscad_version.cmake reads them.
# The archive's members are sorted, owned by root and dated by the tag's commit, so the same input gives the same bytes.
set -euo pipefail
OUT=$(readlink -f "${1:?the output folder}")
CLONE=${2:-}
TAG=openscad-2026.11-RC1
COMMIT=2127234b37d77786a7b5b49b4493b37606c96cd5
VERSION=2026.11~rc1
declare -A SUB=([submodules/manifold]=ce50d78021d64507f89e8c9fc2c2e51018117857
                [submodules/sanitizers-cmake]=bcb1fc68616e9645ca5acea2992412606373ab04)
declare -A URL=([submodules/manifold]=https://github.com/elalish/manifold.git
                [submodules/sanitizers-cmake]=https://github.com/arsenm/sanitizers-cmake.git)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if [ -z "$CLONE" ]; then
	git clone --quiet --no-checkout https://github.com/openscad/openscad.git "$WORK/openscad"
	CLONE=$WORK/openscad
	git -C "$CLONE" fetch --quiet origin "refs/tags/$TAG:refs/tags/$TAG"
fi
got=$(git -C "$CLONE" rev-parse "$TAG^{commit}")
[ "$got" = "$COMMIT" ] || { echo "$TAG is $got here, the recipe is for $COMMIT" >&2; exit 2; }
EPOCH=$(git -C "$CLONE" log -1 --format=%ct "$COMMIT")
ROOT=openscad-$VERSION
mkdir -p "$WORK/tree"
git -C "$CLONE" archive --format=tar --prefix="$ROOT/" "$COMMIT" | tar -x -C "$WORK/tree"
for path in "${!SUB[@]}"; do
	pinned=$(git -C "$CLONE" ls-tree "$COMMIT" "$path" | awk '{print $3}')
	[ "$pinned" = "${SUB[$path]}" ] || { echo "$path: the tag pins $pinned, the recipe ${SUB[$path]}" >&2; exit 2; }
	sub=$WORK/sub-$(basename "$path")
	git init --quiet "$sub"
	git -C "$sub" fetch --quiet --depth 1 "${URL[$path]}" "${SUB[$path]}"
	[ "$(git -C "$sub" rev-parse FETCH_HEAD)" = "${SUB[$path]}" ] || { echo "$path: fetched another commit" >&2; exit 2; }
	rmdir "$WORK/tree/$ROOT/$path"
	git -C "$sub" archive --format=tar --prefix="$ROOT/$path/" FETCH_HEAD | tar -x -C "$WORK/tree"
done
printf '2026.11-RC1\n' > "$WORK/tree/$ROOT/VERSION.txt"
printf '%s\n' "${COMMIT:0:9}" > "$WORK/tree/$ROOT/COMMIT.txt"
mkdir -p "$OUT"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$EPOCH" --format=gnu -C "$WORK/tree" -cf - "$ROOT" |
	xz -6 -T1 > "$OUT/openscad_$VERSION.orig.tar.xz"
sha256sum "$OUT/openscad_$VERSION.orig.tar.xz"
