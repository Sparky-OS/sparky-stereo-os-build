#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-skills-engine (ORDER 430): the program behind `sparky-stereo-skills find|list|context|sections|
# commands|run|mcp|serve`, written in cgm-zig (Daniel's Zig, the `cgm-zig` package; ZIG names it, `zig` by default),
# static, for amd64 only. Its source is sparky-os/skills-mcp, copied as engine-src/ into the source package.
# Usage: OUT=dir ./build-engine.sh        Needs zig, dpkg-dev, binutils and python3.
set -euo pipefail
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the output directory}
ZIG=${ZIG:-zig}
PACKAGE=sparky-stereo-skills-engine
VERSION=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
SRC=${ENGINE_SRC:-$HERE/engine-src}
[ -d "$SRC" ] || SRC=$HERE/../../skills-mcp
TOOLKIT=${SPARKY_LEAN_TOOLKIT:-$HERE/release-toolkit}
if [ ! -d "$TOOLKIT/lean" ]; then TOOLKIT=$(cd "$HERE/../.." && pwd); fi
PROVENANCE=$TOOLKIT/provenance.sh
if [ ! -f "$PROVENANCE" ]; then PROVENANCE=$TOOLKIT/repo/provenance.sh; fi
REPRO=$HERE/../../repo/reproducible.py
[ -f "$REPRO" ] || REPRO=$HERE/build-tools/reproducible.py
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
W=$(mktemp -d "$OUT/.$PACKAGE.XXXXXX")
trap 'rm -rf "$W"' EXIT
# the build works on a copy of the tracked sources, with caches of its own, so nothing of the checkout or the station is read
python3 "${COPY_RECIPE:-$HERE/../../../tools/copy-recipe.py}" "$SRC" "$W/src" >/dev/null
export ZIG_GLOBAL_CACHE_DIR=$W/zig-global ZIG_LOCAL_CACHE_DIR=$W/zig-cache
(cd "$W/src" && "$ZIG" build -Doptimize=ReleaseSmall --prefix "$W/prefix" 2>&1 | grep -v '^info:' || true)
[ -x "$W/prefix/bin/sparky-stereo-skills" ] || { echo "the Zig build failed" >&2; exit 1; }
D=$W/$PACKAGE
install -Dm755 "$W/prefix/bin/sparky-stereo-skills" "$D/usr/libexec/sparky-stereo-skills/engine"
strip --strip-unneeded "$D/usr/libexec/sparky-stereo-skills/engine"
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -Dm644 "$W/src/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
install -Dm644 "$W/src/docs/TREE.md" "$D/usr/share/doc/$PACKAGE/TREE.md"
install -Dm644 "$W/src/docs/CONTRACT.md" "$D/usr/share/doc/$PACKAGE/CONTRACT.md"
mkdir -p "$D/DEBIAN"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" changelog "$HERE/debian/changelog")}
export SOURCE_DATE_EPOCH
find "$D" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Section: devel
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: engine of the Sparky Stereo OS skills, for people and for AI assistants
  One small static program (written in Zig) that finds the skills installed on
  this system, tells which of them apply because their packages are installed,
  and serves them: on the command line (sparky-stereo-skills find, list,
  context, sections, commands, run) and, started by an AI assistant, over the
  Model Context Protocol on stdio (sparky-stereo-skills serve). A package adds a
  skill by shipping a folder under /usr/share/agent-skills/user/ or developer/.
  The program never writes outside the person's own configuration, opens no
  network connection and runs a command only when the person's choice allows it.
EOS
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
bash "$PROVENANCE" --tree "$D"
# Lean Code reads Zig with Zig's own tokenizer (the same compiler as the build)
LEAN_ZIG=${LEAN_ZIG:-$ZIG} PYTHONPATH="$TOOLKIT${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
echo "built $OUT/${PACKAGE}_${VERSION}_amd64.deb"
