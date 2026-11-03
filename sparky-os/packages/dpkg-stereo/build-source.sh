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
COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$P"
mkdir -p "$S/tools"
cp "$COPY" "$S/tools/"
python3 "$COPY" "$ROOT/lean" "$W/lean-inputs"
cp "$W/lean-inputs/"*.py "$W/lean-inputs/JvmLexer.java" "$W/lean-inputs/ZigTokens.zig" "$S/sparky-os/lean/"
cp "$ROOT/repo/provenance.sh" "$S/sparky-os/repo/"
cp "$HERE/copyright" "$S/debian/copyright"
printf '3.0 (native)\n' > "$S/debian/source/format"
cat > "$S/debian/control" <<'EOF'
Source: dpkg-stereo
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Build-Depends: git, sparky-stereo-problems (>= 0.1.0), gcc, node-acorn, nodejs, perl, python3, python3-yaml
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

  * Reconcile 0.1.31 orphan recovery; apply exact independent reproduction
    to older-dpkg pre-invoke and explicit restore before writing a file.
  * Skip pre-invoke conffile restoration only when the running dpkg and
    its installed Provides advertise conffile capability 2.
  * Keep native refusals in the problems engine with their package, path,
    reason and candidate file; repair rechecks without replacing edits.
  * Retain pending conffile records across unpack/configure, cleaning them
    when the unpacked owner is purged before configuration.
  * Share exact original-to-projection validation with the read-only
    conffile verifier for the edition's dpkg (ORDER 376).

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Wed, 04 Nov 2026 12:00:00 -0300

dpkg-stereo (0.1.31) unstable; urgency=medium

  * The records dpkg-stereo 0.1.28 and older lost come back, once: a lean
    file left without its record is recorded again when it is exactly the
    projection of its package's own file at the installed version; any
    other file stays the person's; what cannot be judged yet, because its
    package's .deb is nowhere at hand, is kept as a problem until a later
    run or the person's --repair gives it its record (ORDER 373).
  * A removed package's lean conffiles go back to its package's bytes, so
    installing it again is quiet and projects them again.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 23:30:00 -0300

dpkg-stereo (0.1.30) unstable; urgency=medium

  * Carry Lean Code 0.1.25 and recheck recorded Perl quote refusals once,
    keeping user edits, holds and already qualified projections (ORDER 372).

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 22:00:00 -0300

dpkg-stereo (0.1.29) unstable; urgency=medium

  * A dpkg run that changes nothing costs the hooks almost nothing: the
    program is byte-compiled and imports what it needs when it needs it;
    a configure run gets back only the conffiles of the packages it
    configures; a run that finds dpkg's database and its file lists as
    they were reads no package's fields or list (ORDER 367).
  * A package with its trigger pending, or deconfigured, keeps its records.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 21:00:00 -0300

dpkg-stereo (0.1.28) unstable; urgency=medium

  * --restore fetches the exact version from snapshot.debian.org when no
    cache or configured source has it, checked by SHA-1, control fields and
    every file; what cannot come back is said with the one thing that brings
    it back; --restore --deb FILE.deb takes a person's file of exactly the
    installed version (ORDER 365).

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 18:00:00 -0300

dpkg-stereo (0.1.27) unstable; urgency=medium

  * Pre-depends on the edition's dpkg, which recognizes the Lean Code
    projections of a Multi-Arch: same package's shared files (ORDER 363).

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 15:00:00 -0300

dpkg-stereo (0.1.26) unstable; urgency=medium

  * Use the shared tracked-input copier for recipe and engine inputs; stop on git errors.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 12:00:00 -0300

dpkg-stereo (0.1.25) unstable; urgency=medium

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
