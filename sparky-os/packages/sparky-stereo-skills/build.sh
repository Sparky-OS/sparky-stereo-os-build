#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# Builds sparky-stereo-skills: the public skills of Sparky Stereo OS, with the documents and tools they link to, in
# /usr/share/sparky-stereo-os, and the per-person helper that links them into the AI assistants' skill folders.
# The skills have one source, Sparky-OS/sparky-stereo-os (https://github.com/Sparky-OS/sparky-stereo-os): the files are
# taken from a checkout of it (SKILLS_SRC) at a recorded commit (SKILLS_COMMIT), never copied into this repository.
# A source package carries that snapshot in public/, so it rebuilds without the checkout.
# Usage: OUT=dir ./build.sh   (also writes the source package, .dsc and .tar.xz, into OUT)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the output directory}
VERSION=0.1.0
PACKAGE=sparky-stereo-skills
SKILLS_SRC=${SKILLS_SRC:-/K3D/GitHub/sparky-stereo-os}
SKILLS_COMMIT=${SKILLS_COMMIT:-f350906a101c428a0c6f6a8738a2d93ac1716dbe}
SOURCE_PACKAGE=${SOURCE_PACKAGE:-yes}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
W=$(mktemp -d "$OUT/.$PACKAGE.XXXXXX")
trap 'rm -rf "$W"' EXIT

# The snapshot: skills and tools whole, the documents' Markdown (the skills link to them; their pictures stay online),
# the front page, the credits, the citation and both licences
P=$W/public
if [ -d "$HERE/public" ]; then
	cp -a "$HERE/public" "$P"
	chmod -R u+w "$P"
else
	mkdir -p "$P"
	git -C "$SKILLS_SRC" archive --format=tar "$SKILLS_COMMIT" skills tools docs README.md ATTRIBUTIONS.md CITATION.cff \
		LICENSE LICENSE-GPL-2.0 | tar -x -C "$P"
	find "$P/docs" -type f ! -name '*.md' -delete
	find "$P/docs" -type d -empty -delete
	find "$P" -name .gitignore -delete
	# the guest init scripts and the CI scripts are run as programs: they get the executable bit their #! asks for
	find "$P/tools" "$P/skills" -type f -exec sh -c 'head -c 2 "$1" | grep -q "#!"' _ {} \; -exec chmod 755 {} +
	printf 'https://github.com/Sparky-OS/sparky-stereo-os\ncommit %s\ndate %s\n' "$SKILLS_COMMIT" \
		"$(git -C "$SKILLS_SRC" log -1 --format=%cI "$SKILLS_COMMIT")" >"$P/SOURCE"
fi

D=$W/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE" "$D/usr/share/sparky-stereo-os"
cp -a "$P/." "$D/usr/share/sparky-stereo-os/"
chmod -R u=rwX,go=rX "$D/usr/share/sparky-stereo-os"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -Dm755 "$HERE/bin/sparky-stereo-skills" "$D/usr/bin/sparky-stereo-skills"
mkdir -p "$D/usr/share/sparky/sparky-stereo-skills"
install -m644 "$HERE"/lang/* "$D/usr/share/sparky/sparky-stereo-skills/"
install -Dm644 "$HERE/share/sparky-stereo-skills.desktop" "$D/usr/share/applications/sparky-stereo-skills.desktop"
install -Dm644 "$HERE/share/autostart/sparky-stereo-skills.desktop" "$D/etc/xdg/autostart/sparky-stereo-skills.desktop"
# every file of the package keeps the snapshot's date, so two builds of the same commit are the same
SOURCE_DATE_EPOCH=$(date -d "$(sed -n 's/^date //p' "$P/SOURCE")" +%s)
export SOURCE_DATE_EPOCH
find "$D" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: gawk | mawk, python3, yad
Section: Development
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: Sparky Stereo OS skills for AI assistants
  The public skills of Sparky Stereo OS, from Sparky-OS/sparky-stereo-os,
  with the documents and tools they refer to, in /usr/share/sparky-stereo-os.
  Each person links them into the folders where their AI assistants read
  skills with sparky-stereo-skills (Claude Code, Codex, Gemini CLI, OpenCode,
  GitHub Copilot, Cursor, goose and Cline), or makes an archive for Open
  WebUI; it is offered once at login, and the package itself never writes
  into home folders.
EOF
echo /etc/xdg/autostart/sparky-stereo-skills.desktop >"$D/DEBIAN/conffiles"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${PACKAGE}_${VERSION}_all.deb"
[ "$SOURCE_PACKAGE" = yes ] || exit 0

S=$W/$PACKAGE-$VERSION
mkdir -p "$S/debian/source"
cp -a "$HERE/." "$S/"
rm -rf "$S/public"
cp -a "$P" "$S/public"
cat >"$S/debian/control" <<EOF
Source: $PACKAGE
Section: Development
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.4
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: all
Depends: gawk | mawk, python3, yad
Description: Sparky Stereo OS skills for AI assistants
 The public skills of Sparky Stereo OS, from Sparky-OS/sparky-stereo-os,
 with the documents and tools they refer to, in /usr/share/sparky-stereo-os.
 Each person links them into the folders where their AI assistants read
 skills with sparky-stereo-skills (Claude Code, Codex, Gemini CLI, OpenCode,
 GitHub Copilot, Cursor, goose and Cline), or makes an archive for Open
 WebUI; it is offered once at login, and the package itself never writes
 into home folders.
EOF
cp "$HERE/debian/changelog" "$S/debian/changelog"
cp "$HERE/copyright" "$S/debian/copyright"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOF'
#!/usr/bin/make -f
binary binary-indep:
	OUT=$(CURDIR)/.. SOURCE_PACKAGE=no bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_all.deb Development optional
binary-arch build build-arch build-indep clean:
.PHONY: binary binary-arch binary-indep build build-arch build-indep clean
EOF
chmod +x "$S/debian/rules"
(cd "$W" && dpkg-source -b "$S" >/dev/null)
cp "$W/${PACKAGE}_${VERSION}.dsc" "$W/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
echo "built $OUT/${PACKAGE}_${VERSION}.dsc"
sync
