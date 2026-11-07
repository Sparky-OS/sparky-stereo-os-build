#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/22
# Builds sparky-stereo-skills: the public skills of Sparky Stereo OS, with the documents and tools they link to, in
# /usr/share/sparky-stereo-os, and the per-person helper that links them into the AI assistants' skill folders.
# The skills have one source, Sparky-OS/sparky-stereo-os (https://github.com/Sparky-OS/sparky-stereo-os): the files are
# taken from a checkout of it (SKILLS_SRC) at a recorded commit (SKILLS_COMMIT), never copied into this repository.
# A source package carries that snapshot in public/, so it rebuilds without the checkout.
# Usage: OUT=dir SKILLS_COMMIT=<reviewed-commit> ./build.sh
# Also writes a self-contained source package (.dsc and .tar.xz) into OUT.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO=$HERE/../../repo/reproducible.py
OUT=${OUT:?Set OUT to the output directory}
VERSION=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
PACKAGE=sparky-stereo-skills
SKILLS_SRC=${SKILLS_SRC:-${SPARKY_PUBLIC_EDITION:-}}
SKILLS_COMMIT=${SKILLS_COMMIT:-}
SOURCE_PACKAGE=${SOURCE_PACKAGE:-yes}
COPY=${COPY_RECIPE:-$HERE/../../../tools/copy-recipe.py}
TOOLKIT=${SPARKY_LEAN_TOOLKIT:-$HERE/release-toolkit}
if [ ! -d "$TOOLKIT/lean" ]; then TOOLKIT=$(cd "$HERE/../.." && pwd); fi
PROVENANCE=$TOOLKIT/provenance.sh
if [ ! -f "$PROVENANCE" ]; then PROVENANCE=$TOOLKIT/repo/provenance.sh; fi
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
W=$(mktemp -d "$OUT/.$PACKAGE.XXXXXX")
trap 'rm -rf "$W"' EXIT
RECIPE=$HERE
python3 "$COPY" "$RECIPE" "$W/recipe"
HERE=$W/recipe

# The snapshot: skills and tools whole, the documents' Markdown and architecture
# overview image (large screenshot galleries stay online), the front page,
# the credits, the citation and both licences.
P=$W/public
if [ -d "$HERE/public" ]; then
	python3 "$COPY" "$HERE/public" "$P"
	chmod -R u+w "$P"
	[ -s "$P/SOURCE" ] && [ -s "$P/MANIFEST.sha256" ] || {
		echo 'A bundled snapshot needs SOURCE and MANIFEST.sha256; do not disguise a local candidate as a released commit.' >&2
		exit 1
	}
	python3 - "$P" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
listed = set()
for line in (root / 'MANIFEST.sha256').read_text().splitlines():
    match = re.fullmatch(r'[0-9a-f]{64}  \./(.+)', line)
    if not match or '..' in pathlib.PurePosixPath(match[1]).parts or match[1].startswith('/'):
        sys.exit('Invalid source manifest entry')
    if match[1] in listed:
        sys.exit('Duplicate source manifest entry')
    listed.add(match[1])
actual = set()
for p in root.rglob('*'):
    if p.is_symlink():
        sys.exit('Source snapshot contains a symlink; export ordinary public files')
    if p.is_file() and p != root / 'MANIFEST.sha256':
        actual.add(p.relative_to(root).as_posix())
if listed != actual:
    sys.exit(f'Source manifest file-set mismatch: unlisted={sorted(actual-listed)}, missing={sorted(listed-actual)}')
PY
	(cd "$P" && sha256sum --quiet -c MANIFEST.sha256)
else
	: "${SKILLS_SRC:?Set SKILLS_SRC (or SPARKY_PUBLIC_EDITION) to the public checkout}"
	: "${SKILLS_COMMIT:?Set SKILLS_COMMIT to the reviewed public source commit}"
	SKILLS_COMMIT=$(git -C "$SKILLS_SRC" rev-parse --verify "$SKILLS_COMMIT^{commit}")
	mkdir -p "$P"
	git -C "$SKILLS_SRC" archive --format=tar "$SKILLS_COMMIT" skills tools docs AGENTS.md README.md ATTRIBUTIONS.md CITATION.cff \
		LICENSE LICENSE-GPL-2.0 | tar -x -C "$P"
	find "$P/docs" -type f ! -name '*.md' \
		! -path "$P/docs/images/spatial-computing-architecture.png" -delete
	find "$P/docs" -type d -empty -delete
	find "$P" -name .gitignore -delete
	# the guest init scripts and the CI scripts are run as programs: they get the executable bit their #! asks for
	find "$P/tools" "$P/skills" -type f -exec sh -c 'head -c 2 "$1" | grep -q "#!"' _ {} \; -exec chmod 755 {} +
	printf 'https://github.com/Sparky-OS/sparky-stereo-os\ncommit %s\ndate %s\n' "$SKILLS_COMMIT" \
		"$(git -C "$SKILLS_SRC" log -1 --format=%cI "$SKILLS_COMMIT")" >"$P/SOURCE"
	(cd "$P" && find . -type f ! -path ./MANIFEST.sha256 -print0 | LC_ALL=C sort -z | xargs -0 sha256sum >MANIFEST.sha256)
fi
python3 "$P/tools/check-skills.py"

D=$W/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE" "$D/usr/share/sparky-stereo-os"
cp -a "$P/." "$D/usr/share/sparky-stereo-os/"
# This manifest describes the complete authored source snapshot. Installed tools
# may be projected; their final hashes belong to the package's lc1 manifest.
mv "$D/usr/share/sparky-stereo-os/MANIFEST.sha256" "$D/usr/share/sparky-stereo-os/SOURCE-MANIFEST.sha256"
chmod -R u=rwX,go=rX "$D/usr/share/sparky-stereo-os"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -Dm755 "$HERE/bin/sparky-stereo-skills" "$D/usr/bin/sparky-stereo-skills"
# the standard place for skills (agent-skills/<kind>/<name>): the edition's own tree stays where it is and is named here
mkdir -p "$D/usr/share/agent-skills/paths.d"
printf '# the skills of this package, in the folder the package has always used\ndeveloper /usr/share/sparky-stereo-os/skills\n' >"$D/usr/share/agent-skills/paths.d/sparky-stereo-skills.conf"
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
Depends: gawk | mawk, python3, yad, sparky-stereo-skills-engine (>= $VERSION)
Section: Development
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: Sparky Stereo OS instructions for distribution maintainers
  The public skills of Sparky Stereo OS, from Sparky-OS/sparky-stereo-os,
  with the documents and tools they refer to, in /usr/share/sparky-stereo-os.
  Humans can read them directly, export selected context for local models,
  or extract a complete offline reference bundle. Each person optionally
  links them into the folders where their AI partners read
  skills with sparky-stereo-skills (Claude Code, Codex, Gemini CLI, OpenCode,
  GitHub Copilot, Cursor, goose and Cline), or makes an archive for Open
  WebUI; it is offered once at login, and the package itself never writes
  into home folders. The program that finds, reads and serves the skills (also
  to AI assistants over MCP) is in sparky-stereo-skills-engine.
EOF
echo /etc/xdg/autostart/sparky-stereo-skills.desktop >"$D/DEBIAN/conffiles"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
bash "$PROVENANCE" --tree "$D"
PYTHONPATH="$TOOLKIT${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
echo "built $OUT/${PACKAGE}_${VERSION}_all.deb"
[ "$SOURCE_PACKAGE" = yes ] || exit 0

S=$W/$PACKAGE-$VERSION
mkdir -p "$S/debian/source"
python3 "$COPY" "$HERE" "$S"
mkdir -p "$S/build-tools"
cp "$COPY" "$S/build-tools/"
cp "$REPRO" "$S/build-tools/reproducible.py"
python3 "$COPY" "$RECIPE/../../skills-mcp" "$S/engine-src"
rm -rf "$S/public"
cp -a "$P" "$S/public"
rm -rf "$S/release-toolkit"
mkdir -p "$S/release-toolkit/lean"
cp "$TOOLKIT/lean/"*.py "$TOOLKIT/lean/JvmLexer.java" "$TOOLKIT/lean/ZigTokens.zig" "$S/release-toolkit/lean/"
cp "$PROVENANCE" "$S/release-toolkit/provenance.sh"
if [ -f "$TOOLKIT/LICENSE" ]; then
	cp "$TOOLKIT/LICENSE" "$S/release-toolkit/LICENSE"
else
	cp "$RECIPE/../dpkg-stereo/LICENSE" "$S/release-toolkit/LICENSE"
fi
cat >"$S/debian/control" <<EOF
Source: $PACKAGE
Section: Development
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Build-Depends: git, gcc, node-acorn, nodejs, perl, python3, python3-yaml, binutils, cgm-zig (>= 0.16.0+cgm.0399d2b19b-2+lc1)
Standards-Version: 4.7.4
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: all
Depends: gawk | mawk, python3, yad, sparky-stereo-skills-engine (>= $VERSION)
Description: Sparky Stereo OS instructions for distribution maintainers
 The public skills of Sparky Stereo OS, from Sparky-OS/sparky-stereo-os,
 with the documents and tools they refer to, in /usr/share/sparky-stereo-os.
 Humans can read them directly, export selected context for local models,
 or extract a complete offline reference bundle. Each person optionally
 links them into the folders where their AI partners read
 skills with sparky-stereo-skills (Claude Code, Codex, Gemini CLI, OpenCode,
 GitHub Copilot, Cursor, goose and Cline), or makes an archive for Open
 WebUI; it is offered once at login, and the package itself never writes
 into home folders. The program that finds, reads and serves the skills (also
 to AI assistants over MCP) is in sparky-stereo-skills-engine.

Package: $PACKAGE-engine
Architecture: amd64
Description: engine of the Sparky Stereo OS skills, for people and for AI assistants
 One small static program (written in Zig) that finds the skills installed on
 this system, tells which of them apply because their packages are installed,
 and serves them on the command line and, started by an AI assistant, over the
 Model Context Protocol on stdio.
EOF
cp "$HERE/debian/changelog" "$S/debian/changelog"
cp "$HERE/copyright" "$S/debian/copyright"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOF'
#!/usr/bin/make -f
binary-indep:
	OUT=$(CURDIR)/.. COPY_RECIPE=$(CURDIR)/build-tools/copy-recipe.py SOURCE_PACKAGE=no bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_all.deb Development optional
	if test -f ../sparky-stereo-skills-lc-hr_$$(dpkg-parsechangelog -S Version)_all.deb; then dpkg-distaddfile sparky-stereo-skills-lc-hr_$$(dpkg-parsechangelog -S Version)_all.deb doc optional; sed -i '/^sparky-stereo-skills-lc-hr_/s/$$/ automatic=yes/' debian/files; fi
binary-arch:
	OUT=$(CURDIR)/.. COPY_RECIPE=$(CURDIR)/build-tools/copy-recipe.py bash ./build-engine.sh
	dpkg-distaddfile sparky-stereo-skills-engine_$$(dpkg-parsechangelog -S Version)_amd64.deb Development optional
binary: binary-indep binary-arch
build build-arch build-indep clean:
.PHONY: binary binary-arch binary-indep build build-arch build-indep clean
EOF
chmod +x "$S/debian/rules"
# the source tree is dated like the package (the snapshot's date) and its modes normalized, so the checkout time and the umask stay out (ORDER 421b)
python3 "$REPRO" normalize "$SOURCE_DATE_EPOCH" "$S"
(cd "$W" && dpkg-source -b "$S" >/dev/null)
cp "$W/${PACKAGE}_${VERSION}.dsc" "$W/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
echo "built $OUT/${PACKAGE}_${VERSION}.dsc"
sync
