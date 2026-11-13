#!/bin/bash
# Sparky Stereo OS: builds the Craft suite's programs and shared libraries in the generated workspace, one cargo run
# for the apps that embed the same pinned fonts and catalogues (they are read from one environment variable). Offline and locked: a crate, a font folder or a catalogue folder that is missing stops the build.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Usage: suite-build.sh SOURCE WORKSPACE [APP...]   (SOURCE_DATE_EPOCH dates the programs' build date)
# Last update 2026/11/13
set -euo pipefail
src=$(cd "$1" && pwd); ws=$(cd "$2" && pwd); shift 2
tools=${SUITE_TOOLS:-$src/debian}
json=$tools/suite.json
: "${SOURCE_DATE_EPOCH:?the build date of the programs is the date of the source, never the clock}"
apps=("$@"); [ ${#apps[@]} -gt 0 ] || mapfile -t apps < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["build"]))' "$json")
# the edition's compiler only: the libraries load libstd by the name this compiler gives it
ours=$(dpkg-query -W -f '${Version}' rustc 2>/dev/null || true)
case "$ours" in *+stereo3d*) echo "rustc $ours: $(rustc --version)" ;; *) echo "the compiler is not the edition's build (rustc package version: ${ours:-none}); the suite is built with ours only" >&2; exit 1 ;; esac
field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["apps"][sys.argv[2]][sys.argv[3]]; print("" if v is None else (" ".join(v) if isinstance(v, list) else v))' "$json" "$1" "$2"; }
date=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%d)
cd "$ws"
# Every cargo run selects every program of every app, so the resolve (the features of every crate, the build
# scripts' and procedural macros' side included) is the same in each run. Apps that embed the same fonts and
# catalogues are built by one run; an app with other pinned inputs gets a run of its own with its environment, and
# only its own files are taken from that run.
all=(); allfeats=(); ids=()
declare -A group
for a in "${apps[@]}"; do
	for b in $(field "$a" bins); do all+=(-p "$b"); done
	f=$(field "$a" features); [ -z "$f" ] || allfeats+=($f)
	ids+=("${a^^}_BUILD_SHA=$(field "$a" rev)" "${a^^}_BUILD_DATE=$date")
	key="$(field "$a" fonts)|$(field "$a" i18n)"
	group[$key]="${group[$key]:-} $a"
done
featlist=$(IFS=,; echo "${allfeats[*]}")
mkdir -p built
common=
for key in $(printf '%s\n' "${!group[@]}" | LC_ALL=C sort); do
	fontrev=${key%%|*}; i18n=${key#*|}
	fonts=$src/fonts/craft-fonts-${fontrev:0:8}
	[ -f "$fonts/fonts/manifest.txt" ] || { echo "${group[$key]}: the pinned fonts are not in the source: $fonts" >&2; exit 1; }
	env=(CRAFT_FONTS_DIR="$fonts" CRAFT_FONTS_REQUIRED=1 "${ids[@]}")
	if [ -n "$i18n" ]; then
		[ -d "$src/i18n/craft-i18n-${i18n:0:8}/locales" ] || { echo "${group[$key]}: the pinned catalogues are not in the source" >&2; exit 1; }
		env+=(CRAFT_I18N_DIR="$src/i18n/craft-i18n-${i18n:0:8}" CRAFT_I18N_REQUIRED=1)
	fi
	echo "==${group[$key]}: fonts ${fontrev:0:8}, catalogues ${i18n:0:8}: cargo build --release --locked --offline ${all[*]} ${featlist:+--features $featlist} --bins"
	env "${env[@]}" cargo build --release --locked --offline "${all[@]}" ${featlist:+--features "$featlist"} --bins
	# the common library must be the same file after every run: a run that builds it again would leave the programs
	# taken from an earlier run linked to a library that no longer exists
	now=$(sha256sum "$CARGO_TARGET_DIR/release/libcraft_suite_shared.so" | cut -d' ' -f1)
	if [ -n "$common" ] && [ "$now" != "$common" ]; then
		echo "${group[$key]}: this run rebuilt the common library (was $common, is $now)" >&2
		exit 1
	fi
	common=$now
	cp "$CARGO_TARGET_DIR/release/libcraft_suite_shared.so" built/
	for a in ${group[$key]}; do
		rm -rf "built/$a"; mkdir -p "built/$a"
		cp "$CARGO_TARGET_DIR/release/lib${a}_shared.so" "built/$a/"
		for b in $(field "$a" bins); do cp "$CARGO_TARGET_DIR/release/$b" "built/$a/"; done
	done
done
echo "built: $(ls built | tr '\n' ' '); the common library is $common"
