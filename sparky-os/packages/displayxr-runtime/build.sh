#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the DisplayXR OpenXR runtime from its release tag (ORDER 58 with 187), with the packaging of
# Sparky-OS/displayxr-packaging, through the Lean Code toolkit (release/build-dh-lean.sh), in a throwaway Debian
# testing container with the edition's repository pinned at 1001.
# The source package has four upstream tarballs, each checked before it is used:
#   displayxr-runtime_V.orig.tar.xz                     git archive of the tag (its commit checked)
#   displayxr-runtime_V.orig-displayxr-mcp.tar.xz       displayxr-mcp at the tag the runtime's CMake fetches
#   displayxr-runtime_V.orig-displayxr-common.tar.xz    displayxr-common at the tag the runtime's CMake fetches
#   displayxr-runtime_V.orig-release.tar.xz             DisplayXR's own release package, for the dashboard (.NET),
#                                                       its SHA-256 the digest the GitHub release lists
# so the build reads no network, and what is shipped can be compared with what DisplayXR released.
# Usage: build.sh OUT PACKAGING_CLONE [PACKAGING_COMMIT]
#   OUT               empty folder for the results (source, binaries, Lean Code companions)
#   PACKAGING_CLONE   a clone of Sparky-OS/displayxr-packaging holding PACKAGING_COMMIT (by default the commit below)
# REPO (default /var/tmp/sparky-repo-current) is the edition's repository; SPARKY_LC_ARCHIVE_DIR the link gate's folder
# (release/build-dh-lean.sh); SPARKY_SCRATCH the parent of the throwaway work folder.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?empty output folder}")
CLONE=$(realpath "${2:?clone of Sparky-OS/displayxr-packaging}")
PACKAGING_COMMIT=${3:-58b8e4849ed5d3173a6d82f0c4e825d33a077bba}
REPO=${REPO:-/var/tmp/sparky-repo-current}
UPV=2.66.3
RUNTIME_COMMIT=c96f08b7ca5b57418123da0741a4a7bd6346a402
MCP_TAG=v0.5.6
MCP_COMMIT=e10a722ad20b59d667044833758c51faf7c253e8
COMMON_TAG=v1.2.0
COMMON_COMMIT=917adf4719acc4f6787a5978b24f5f0c20f9994e
RELEASE_DEB=displayxr-runtime_${UPV}_amd64.deb
RELEASE_SHA256=7d216f4557d4eb54d5563a748c9f144218c79ab4a2ea48fd36fc5a216e7e8aaa
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/displayxr-runtime.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

fetch() {  # fetch URL TAG COMMIT DIR
	git clone -q --depth 1 --branch "$2" "$1" "$4" 2>/dev/null
	[ "$(git -C "$4" rev-parse HEAD)" = "$3" ] || { echo "$1 tag $2 is not $3" >&2; exit 1; }
}
fetch https://github.com/DisplayXR/displayxr-runtime.git "v$UPV" "$RUNTIME_COMMIT" "$WORK/up"
fetch https://github.com/DisplayXR/displayxr-mcp.git "$MCP_TAG" "$MCP_COMMIT" "$WORK/mcp"
fetch https://github.com/DisplayXR/displayxr-common.git "$COMMON_TAG" "$COMMON_COMMIT" "$WORK/common"
# the tags the runtime's CMake fetches are the ones carried
grep -Eq "^[[:space:]]*GIT_TAG ${MCP_TAG//./\\.}\)?\$" "$WORK/up/CMakeLists.txt" || { echo "the runtime no longer fetches displayxr-mcp $MCP_TAG" >&2; exit 1; }
grep -Eq "^[[:space:]]*GIT_TAG ${COMMON_TAG//./\\.}\)?\$" "$WORK/up/src/xrt/auxiliary/math/CMakeLists.txt" || { echo "the runtime no longer fetches displayxr-common $COMMON_TAG" >&2; exit 1; }
git -C "$WORK/up" archive --format=tar --prefix="displayxr-runtime-$UPV/" "$RUNTIME_COMMIT" | xz -6 > "$WORK/displayxr-runtime_$UPV.orig.tar.xz"
git -C "$WORK/mcp" archive --format=tar --prefix=displayxr-mcp/ "$MCP_COMMIT" | xz -6 > "$WORK/displayxr-runtime_$UPV.orig-displayxr-mcp.tar.xz"
git -C "$WORK/common" archive --format=tar --prefix=displayxr-common/ "$COMMON_COMMIT" | xz -6 > "$WORK/displayxr-runtime_$UPV.orig-displayxr-common.tar.xz"
mkdir "$WORK/release"
curl -fsSL -o "$WORK/release/$RELEASE_DEB" "https://github.com/DisplayXR/displayxr-runtime/releases/download/v$UPV/$RELEASE_DEB"
echo "$RELEASE_SHA256  $WORK/release/$RELEASE_DEB" | sha256sum -c -
# the release tarball is dated by the tag's commit, so the same release gives the same bytes
STAMP=$(git -C "$WORK/up" log -1 --format=%ct "$RUNTIME_COMMIT")
tar --sort=name --mtime="@$STAMP" --owner=0 --group=0 --numeric-owner --mode=a+rX,u+w,go-w -C "$WORK" -cf - release |
	xz -6 > "$WORK/displayxr-runtime_$UPV.orig-release.tar.xz"
rm -rf "$WORK/up" "$WORK/mcp" "$WORK/common" "$WORK/release"
SRC=displayxr-runtime-$UPV
tar -xJf "$WORK/displayxr-runtime_$UPV.orig.tar.xz" -C "$WORK"
for c in displayxr-mcp displayxr-common release; do
	tar -xJf "$WORK/displayxr-runtime_$UPV.orig-$c.tar.xz" -C "$WORK/$SRC"
done
# the packaging: only its tracked debian/ at the commit, never the clone's working tree
git -C "$CLONE" archive --format=tar "$PACKAGING_COMMIT" debian | tar -x -C "$WORK/$SRC"
echo "packaging: $(git -C "$CLONE" rev-parse "$PACKAGING_COMMIT")"
DEBV=$(dpkg-parsechangelog -l "$WORK/$SRC/debian/changelog" -S Version)
[ "${DEBV%-*}" = "$UPV" ] || { echo "debian/changelog is $DEBV, not $UPV" >&2; exit 1; }
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "$SRC" "$DEBV+lc1" "$REPO"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
