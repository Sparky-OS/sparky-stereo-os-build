#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# The part of round-supply-chain.sh that runs inside the tools container: /dest (the tree), /toolkit (sparky-os),
# /out (OUT, with work/stagedirs.txt) and ROUND. Every step is checked; the first failure stops it.
set -euo pipefail
R=/toolkit/release PY=/opt/v/bin/python
: "${ROUND:?}"
NAME=sparky-stereo-os-mashtabba-$ROUND
P=/out/publish W=/out/work
exec > "$W/round.log" 2>&1
BUILD_DIRS=()
while IFS= read -r dir; do BUILD_DIRS+=(--build-dir "$dir"); done < "$W/stagedirs.txt"
"$PY" -I "$R/make-sbom.py" --tree /dest --name "$NAME" --out "$P/$NAME.spdx.json" --report "$W/sbom-report.json" --cache "$W/cache.json"
"$PY" -I "$R/check-supply-chain.py" sbom "$P/$NAME.spdx.json" --tree /dest
"$PY" -I "$R/make-provenance.py" --tree /dest "${BUILD_DIRS[@]}" --recipes-dir /toolkit/packages --recipes-dir /toolkit/upstream \
	--out-dir "$W/provenance" --bundle "$P/provenance-$ROUND.intoto.jsonl" --report "$P/provenance-gaps.json" --cache "$W/cache.json"
"$PY" -I "$R/check-supply-chain.py" provenance "$W/provenance" --tree /dest
cd "$P"
EXTRA=()
# ORDER 428: which toolkit made the tree (the round runs from a frozen worktree of the build repository at this commit)
if [ -n "${ROUND_BUILD_COMMIT:-}" ]; then
	[[ $ROUND_BUILD_COMMIT =~ ^[0-9a-f]{40}$ ]] || { echo "ROUND_BUILD_COMMIT is not a full commit id: $ROUND_BUILD_COMMIT" >&2; exit 1; }
	printf '{\n  "round": "%s",\n  "buildRepository": "https://github.com/Sparky-OS/sparky-stereo-os-build",\n  "buildRepositoryCommit": "%s"\n}\n' \
		"$ROUND" "$ROUND_BUILD_COMMIT" > "round-toolkit-$ROUND.json"
	EXTRA=("round-toolkit-$ROUND.json")
else
	echo "note: ROUND_BUILD_COMMIT is not set; the round's toolkit commit is not in the published statement set"
fi
sha256sum -- "$NAME.spdx.json" "provenance-$ROUND.intoto.jsonl" provenance-gaps.json "${EXTRA[@]}" > SHA256SUMS
sha256sum --check --quiet SHA256SUMS
