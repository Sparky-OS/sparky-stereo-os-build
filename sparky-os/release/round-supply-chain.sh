#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# Part 1 step of a publication round (ORDER 394b): the bill of materials and the build provenance of the finished tree.
# Runs in the supply-chain tools container (release/supply-chain-image), after publish-tree.sh returned 0 and the tree
# is synced to disk. Writes nothing into DEST and signs and sends nothing: the detached signature of SHA256SUMS (Part 2)
# and the upload (sync-supply-chain.sh) belong to the main session. Any failure stops with a non-zero exit.
#
# Usage: round-supply-chain.sh DEST ROUND OUT STAGEDIRS
#   DEST       the finished repository tree (read only)
#   ROUND      the round's name, e.g. r1103a
#   OUT        an empty or new folder: OUT/publish holds the files to publish (and SHA256SUMS), OUT/work the rest
#   STAGEDIRS  a file with one folder per line (the round's stage folders); build records and .buildinfo files are searched
#              below each, read only
# The image is SPARKY_SUPPLY_CHAIN_IMAGE (default sparky-supply-chain-tools:1, built from release/supply-chain-image).
# A DEST made of symlinks (a publication copy that links the pool) needs the folders its links point into:
# SPARKY_SUPPLY_CHAIN_MOUNTS="/abs/dir /abs/dir2" mounts each read only at the same path.
# ROUND_BUILD_COMMIT (ORDER 428, optional but set by official-part1.sh): the full commit of the build repository the round
# ran from (round-worktree.sh). It is written into OUT/publish/round-toolkit-ROUND.json, which SHA256SUMS lists, so the
# detached signature covers the statement of which toolkit made the tree. Without it the file is not made and the run says so.
# Last update 2026/11/06
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 4 ] || { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
DEST=$(realpath "$1") ROUND=$2 OUT=$3 STAGEDIRS=$(realpath "$4")
IMAGE=${SPARKY_SUPPLY_CHAIN_IMAGE:-sparky-supply-chain-tools:1}
[[ $ROUND =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad round name: $ROUND" >&2; exit 2; }
for need in "dists/mashtabba/InRelease" pool; do
	[ -e "$DEST/$need" ] || { echo "$DEST is not a finished tree: $need is missing" >&2; exit 1; }
done
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
mkdir -p "$OUT/publish" "$OUT/work"
MOUNTS=()
while IFS= read -r dir || [ -n "$dir" ]; do
	[ -n "$dir" ] || continue
	case $dir in /* ) ;; *) echo "STAGEDIRS: $dir is not an absolute path" >&2; exit 1 ;; esac
	case $dir in *[:,\ ]* ) echo "STAGEDIRS: $dir has a character a mount cannot take" >&2; exit 1 ;; esac
	[ -d "$dir" ] || { echo "STAGEDIRS: $dir is not a folder" >&2; exit 1; }
	MOUNTS+=(-v "$dir":"$dir":ro)
	printf '%s\n' "$dir" >> "$OUT/work/stagedirs.txt"
done < "$STAGEDIRS"
for dir in ${SPARKY_SUPPLY_CHAIN_MOUNTS:-}; do
	case $dir in /*) [ -d "$dir" ] && MOUNTS+=(-v "$dir":"$dir":ro) || { echo "SPARKY_SUPPLY_CHAIN_MOUNTS: $dir is not a folder" >&2; exit 1; } ;;
	*) echo "SPARKY_SUPPLY_CHAIN_MOUNTS: $dir is not an absolute path" >&2; exit 1 ;;
	esac
done
[ -s "$OUT/work/stagedirs.txt" ] || { echo "STAGEDIRS lists no folder" >&2; exit 1; }
# the container writes its output to OUT/work/round.log (the docker stream can lose the last lines of a short run)
status=0
docker run --rm --network none --user "$(id -u):$(id -g)" --cpus 4 -e HOME=/out -e ROUND="$ROUND" -e ROUND_BUILD_COMMIT="${ROUND_BUILD_COMMIT:-}" \
	-v "$DEST":/dest:ro -v "$HERE/..":/toolkit:ro -v "$OUT":/out "${MOUNTS[@]}" \
	"$IMAGE" bash /toolkit/release/round-supply-chain-inner.sh || status=$?
cat "$OUT/work/round.log" 2>/dev/null || true
[ "$status" = 0 ] || { echo "round-supply-chain.sh: the container failed with exit $status; see $OUT/work/round.log" >&2; exit "$status"; }
echo "== supply chain of $ROUND is in $OUT/publish (unsigned):"
cat "$OUT/publish/SHA256SUMS"
