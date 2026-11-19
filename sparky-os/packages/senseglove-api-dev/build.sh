#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# The SenseGlove C++ API's headers and example, from SenseGlove's repository at one commit (sources.tsv: size and SHA-256 of
# every file), as a development package. The two libraries have no published source: they are not in this package
# (see README.Debian); the Stereo APTus entry fetches them from SenseGlove.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
COMMIT=31900b320aa0e84cb976ebef976dac6330f73fac
VERSION=0.22+20250801+lc1
PACKAGE=senseglove-api-dev
BASE=https://raw.githubusercontent.com/Adjuvo/SenseGlove-API/$COMMIT
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.senseglove-api.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
DOC=$D/usr/share/doc/$PACKAGE
mkdir -p "$D/DEBIAN" "$DOC/examples" "$D/usr/include" "$D/usr/lib/cmake/SenseGlove"
n=0
while IFS=$'\t' read -r path size sha; do
	[ -n "$path" ] || continue
	case "$path" in
		include/SenseGlove/*.hpp|include/SenseGlove/*/*.hpp) dest=$D/usr/$path ;;
		examples/sgcore-client.cpp) dest=$DOC/examples/sgcore-client.cpp ;;
		LICENSE) dest=$DOC/LICENSE.SenseGlove ;;
		README.md) dest=$DOC/README.SenseGlove-API.md ;;
		*) echo "$path: not a path this package takes" >&2; exit 1 ;;
	esac
	mkdir -p "$(dirname "$dest")"
	curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 \
		--output "$dest" "$BASE/$path"
	[ "$(stat -c %s "$dest")" = "$size" ] || { echo "$path: size differs from sources.tsv" >&2; exit 1; }
	[ "$(sha256sum "$dest" | cut -d' ' -f1)" = "$sha" ] || { echo "$path: SHA-256 differs from sources.tsv" >&2; exit 1; }
	chmod 644 "$dest"
	n=$((n + 1))
done <"$HERE/sources.tsv"
[ "$n" = "$(grep -c . "$HERE/sources.tsv")" ]
install -m644 "$HERE/cmake/SenseGloveConfig.cmake" "$HERE/cmake/SenseGloveConfigVersion.cmake" "$D/usr/lib/cmake/SenseGlove/"
install -m644 "$HERE/examples/CMakeLists.txt" "$DOC/examples/CMakeLists.txt"
install -m644 "$HERE/README.Debian" "$DOC/README.Debian"
install -m644 "$HERE/copyright" "$DOC/copyright"
install -m644 "$HERE/README.md" "$HERE/CHANGELOG" "$HERE/sources.tsv" "$DOC/"
printf 'https://github.com/Adjuvo/SenseGlove-API\n%s\n' "$COMMIT" >"$DOC/SOURCE"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOT
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Section: libdevel
Priority: optional
Homepage: https://sparkylinux.org
Suggests: cmake, clang, libc++-dev, libc++abi-dev
Description: SenseGlove C++ API: headers, CMake package and example
 The 61 headers of SenseGlove's C++ API (SGCore and SGConnect) and its
 example, taken from SenseGlove's repository at one commit and checked
 against their SHA-256, with a CMake package (find_package(SenseGlove)).
 The two libraries have no published source and are not in this package:
 install the Stereo APTus entry "SenseGlove API libraries (C++)", which
 fetches them from SenseGlove when you ask for it (about 2.8 MiB).
 .
 Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł
 "pavroo" Pijanowski). The headers are SenseGlove B.V.'s, under the MIT licence.
EOT
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"

sync
