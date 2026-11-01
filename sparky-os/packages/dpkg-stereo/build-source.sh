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
mkdir -p "$S/sparky-os/packages" "$S/sparky-os/lean" "$S/sparky-os/repo" "$S/debian/source"
cp -a "$HERE" "$S/sparky-os/packages/dpkg-stereo"
cp "$ROOT/lean/"*.py "$ROOT/lean/JvmLexer.java" "$S/sparky-os/lean/"
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

  * The lean toolkit 0.1.23's link gate resolves an ELF file with its
    package's own Recommends installed where every library it misses is
    shipped by a package those Recommends name, and notes it (ORDER 311
    step 4: fltk1.4-games' flpuzzle, whose GL libraries Debian sends to
    Recommends with dpkg-shlibdeps -dRecommends). Debian Policy 7.2:
    Recommends lists "packages that would be found together with this one
    in all but unusual installations". The previous build is treated the
    same way; Depends-only resolution stays the rule for everything else,
    and a library no Depends and no such Recommends provides still fails.
  * dpkg-stereo itself is 0.1.23's, unchanged.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sun, 01 Nov 2026 18:00:00 -0300
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
