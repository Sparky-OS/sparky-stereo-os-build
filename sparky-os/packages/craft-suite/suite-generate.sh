#!/bin/bash
# Sparky Stereo OS: generates the Craft suite's one workspace and its shared libraries from the unpacked source.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Usage: suite-generate.sh SOURCE OUT [APP...]
#   SOURCE holds apps/, vendor/ and this recipe's files (suite.json, suite-tree.py, suite-source.py, suite-trees.sh,
#   suite-fixups.json, and suite-Cargo.lock when the source pins the resolve); OUT is the workspace to write, at the path
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
# the few lines one resolve needs changed in the generated copy (never in upstream's files): each names its line
# whole, so it applies to the authored and to the lean form alike, and stops when the line is not there exactly once
python3 - "$tools/suite-fixups.json" "$out" "${apps[@]}" <<'PY'
import json, sys
from pathlib import Path
fixups, out, apps = json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]), sys.argv[3:]
for f in fixups:
    if f['app'] not in apps:
        continue
    path = out / f['app'] / f['file']
    lines = path.read_text().split('\n')
    at = [i for i, line in enumerate(lines) if line == f['old']]
    if len(at) != 1:
        sys.exit(f"{path}: the line to change is there {len(at)} times, not once: {f['old']!r}")
    lines[at[0]] = f['new']
    path.write_text('\n'.join(lines))
    print(f"changed in the generated copy: {f['app']}/{f['file']}: {f['why']}")
PY
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
