#!/bin/bash
# Sparky Stereo OS: generates the Craft suite's one workspace and its shared libraries from the unpacked source.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Usage: suite-generate.sh SOURCE OUT [APP...]
#   SOURCE holds apps/, vendor/ and this recipe's files (suite.json, suite-tree.py, suite-source.py, suite-trees.sh,
#   suite-patches/, and suite-Cargo.lock when the source pins the resolve); OUT is the workspace to write, at the path
#   it is built at (the generated crates name their members by absolute path). Nothing is fetched: every source is
#   replaced by its folder under SOURCE/vendor, and a crate that is not there stops cargo.
# The compiler in PATH names the libraries: its `rustc -vV` enters every library's name.
# Last update 2026/11/13
set -euo pipefail
src=$(cd "$1" && pwd); out=$2; shift 2
tools=${SUITE_TOOLS:-$src/debian}
json=$tools/suite.json
apps=("$@"); [ ${#apps[@]} -gt 0 ] || mapfile -t apps < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["build"]))' "$json")
python3 "$tools/suite-tree.py" tree "$out" "$json" "$src/apps" "${apps[@]}"
cd "$out"
mkdir -p .cargo
python3 "$tools/suite-source.py" config "$src/vendor" "$src/vendor" >.cargo/config.toml
for p in "$tools"/suite-patches/*.patch; do
	app=$(basename "$p" | cut -d- -f2)
	case " ${apps[*]} " in *" $app "*) patch -s -p1 <"$p"; echo "applied $(basename "$p")" ;; esac
done
bins=(); feats=(); groups=()
for a in "${apps[@]}"; do
	mapfile -t b < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["apps"][sys.argv[2]]["bins"]))' "$json" "$a")
	mapfile -t f < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["apps"][sys.argv[2]]["features"]))' "$json" "$a")
	bins+=("${b[@]}"); feats+=("${f[@]}"); groups+=("$(IFS=,; echo "${b[*]}")")
	export "SUITE_APP_SEED_${a^^}=$(python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["apps"][sys.argv[2]]; print(a["rev"], sorted(a["libs"].items()), a["fonts"], a["i18n"])' "$json" "$a")"
done
featlist=$(IFS=,; echo "${feats[*]}")
SUITE_TREE_FEATURES=$featlist bash "$tools/suite-trees.sh" "$out" "$out/trees" "$featlist" "${bins[@]}" >/dev/null
cargo metadata --offline --format-version 1 --filter-platform x86_64-unknown-linux-gnu ${featlist:+--features "$featlist"} >"$out/metadata.json"
SUITE_ABI_SEED="$(rustc -vV)" PER_APP=1 python3 "$tools/suite-tree.py" shared "$out" "$out/metadata.json" "$out/trees" "${groups[@]}"
if [ -f "$tools/suite-Cargo.lock" ] && [ "${SUITE_LOCK:-pinned}" = pinned ]; then
	cp "$tools/suite-Cargo.lock" Cargo.lock
	cargo metadata --locked --offline --format-version 1 >/dev/null
	echo "the resolve is the source's pinned suite-Cargo.lock"
else
	cargo metadata --offline --format-version 1 >/dev/null
	echo "the resolve was made here: $(grep -c '^\[\[package\]\]' Cargo.lock) packages"
fi
