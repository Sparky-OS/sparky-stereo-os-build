#!/bin/bash
# Sparky Stereo OS: builds the Craft suite's programs and shared libraries in the generated workspace, one cargo run
# per app, because each app embeds the fonts and catalogues of its own pinned revision and reads them from one
# environment variable. Offline and locked: a crate, a font folder or a catalogue folder that is missing stops the build.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Usage: suite-build.sh SOURCE WORKSPACE [APP...]   (SOURCE_DATE_EPOCH dates the programs' build date)
# Last update 2026/11/13
set -euo pipefail
src=$(cd "$1" && pwd); ws=$(cd "$2" && pwd); shift 2
tools=${SUITE_TOOLS:-$src/debian}
json=$tools/suite.json
: "${SOURCE_DATE_EPOCH:?the build date of the programs is the date of the source, never the clock}"
apps=("$@"); [ ${#apps[@]} -gt 0 ] || mapfile -t apps < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["apps"]))' "$json")
# the edition's compiler only: the libraries load libstd by the name this compiler gives it
ours=$(dpkg-query -W -f '${Version}' rustc 2>/dev/null || true)
case "$ours" in *+stereo3d*) echo "rustc $ours: $(rustc --version)" ;; *) echo "the compiler is not the edition's build (rustc package version: ${ours:-none}); the suite is built with ours only" >&2; exit 1 ;; esac
field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["apps"][sys.argv[2]][sys.argv[3]]; print("" if v is None else (" ".join(v) if isinstance(v, list) else v))' "$json" "$1" "$2"; }
date=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%d)
cd "$ws"
for a in "${apps[@]}"; do
	fonts=$src/fonts/craft-fonts-$(field "$a" fonts | cut -c1-8)
	[ -f "$fonts/fonts/manifest.txt" ] || { echo "$a: its pinned fonts are not in the source: $fonts" >&2; exit 1; }
	env=(CRAFT_FONTS_DIR="$fonts" CRAFT_FONTS_REQUIRED=1 "${a^^}_BUILD_SHA=$(field "$a" rev)" "${a^^}_BUILD_DATE=$date")
	i18n=$(field "$a" i18n)
	if [ -n "$i18n" ]; then
		[ -d "$src/i18n/craft-i18n-${i18n:0:8}/locales" ] || { echo "$a: its pinned catalogues are not in the source" >&2; exit 1; }
		env+=(CRAFT_I18N_DIR="$src/i18n/craft-i18n-${i18n:0:8}" CRAFT_I18N_REQUIRED=1)
	fi
	args=(); for b in $(field "$a" bins); do args+=(-p "$b"); done
	feats=$(field "$a" features | tr ' ' ,)
	echo "== $a: cargo build --release --locked --offline ${args[*]} ${feats:+--features $feats} --bins"
	env "${env[@]}" cargo build --release --locked --offline "${args[@]}" ${feats:+--features "$feats"} --bins
done
