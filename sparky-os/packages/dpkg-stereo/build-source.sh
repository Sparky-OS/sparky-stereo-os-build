#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
# Bundle the authored builder and engine, preserving their relative source layout.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:?Set OUT to the source output directory}
VERSION=$(sed -n 's/^VERSION=//p' "$HERE/build.sh")
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
W=$(mktemp -d "$OUT/.dpkg-stereo-source.XXXXXX")
trap 'rm -rf "$W"' EXIT
S=$W/dpkg-stereo-$VERSION
P=$S/sparky-os/packages/dpkg-stereo
mkdir -p "$P" "$S/sparky-os/lean" "$S/sparky-os/repo" "$S/debian/source"
# The recipe folder as git tracks it, so what a working checkout made beside it (bin/__pycache__ and *.pyc from
# running bin/dpkg-stereo there, editor and test leftovers) never ships in the source package. Outside a git work
# tree (an unpacked source package, an export) the folder is copied without __pycache__ folders and *.pyc files.
if git -C "$HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "build-source: the recipe's files as git tracks them"
	(cd "$HERE" && git ls-files -z -- . | xargs -0r cp -a --parents -t "$P")
else
	echo "build-source: no git work tree; the recipe folder without __pycache__ and *.pyc"
	(cd "$HERE" && find . -name __pycache__ -prune -o ! -type d ! -name '*.pyc' -print0 | xargs -0r cp -a --parents -t "$P")
fi
cp "$ROOT/lean/"*.py "$ROOT/lean/JvmLexer.java" "$ROOT/lean/ZigTokens.zig" "$S/sparky-os/lean/"
cp "$ROOT/repo/provenance.sh" "$S/sparky-os/repo/"
cp "$HERE/copyright" "$S/debian/copyright"
printf '3.0 (native)\n' > "$S/debian/source/format"
cat > "$S/debian/control" <<'EOF'
Source: dpkg-stereo
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml
Standards-Version: 4.7.4
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: dpkg-stereo
Architecture: all
Depends: dpkg, python3
Description: Lean Code for installed packages
 Qualified payload projection and recovery of matching authored source.
EOF
cat > "$S/debian/changelog" <<EOF
dpkg-stereo ($VERSION) unstable; urgency=medium

  * Nothing fails silently (ORDER 346b, rows U19, U20, U57 and U58): a step
    that cannot do what it is for says what failed, why and what to do, in
    the nine languages, and keeps it in /var/lib/dpkg-stereo/problems until
    it next succeeds; --problems, --repair, --dismiss and --notify (a
    session unit shows each problem once). dpkg's and APT's hooks still
    return 0, because dpkg and APT stop when a hook fails.
  * --verify --deep exits 2 and names the reason when a file could not be
    compared with its package's .deb; --restore, --hr and --fetch-hr name
    the same reasons.
  * A Python bytecode cache that cannot be refreshed is kept with its file
    and interpreter, and the records are saved before the refresh.
  * The lean toolkit's link gate blocks when readelf or nm cannot read an
    ELF file's inventory; the renderer identity stays as it was.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 -0300
EOF
cat > "$S/debian/rules" <<'EOF'
#!/usr/bin/make -f
binary binary-indep:
	OUT=$(CURDIR)/.. bash sparky-os/packages/dpkg-stereo/build.sh
	dpkg-distaddfile dpkg-stereo_$$(dpkg-parsechangelog -S Version)_all.deb System optional
	if test -f ../dpkg-stereo-lc-hr_$$(dpkg-parsechangelog -S Version)_all.deb; then dpkg-distaddfile dpkg-stereo-lc-hr_$$(dpkg-parsechangelog -S Version)_all.deb doc optional; sed -i '/^dpkg-stereo-lc-hr_/s/$$/ automatic=yes/' debian/files; fi
binary-arch build build-arch build-indep clean:
.PHONY: binary binary-arch binary-indep build build-arch build-indep clean
EOF
chmod +x "$S/debian/rules"
(cd "$W" && dpkg-source -b "$S")
cp "$W/dpkg-stereo_$VERSION.dsc" "$W/dpkg-stereo_$VERSION.tar.xz" "$OUT/"
