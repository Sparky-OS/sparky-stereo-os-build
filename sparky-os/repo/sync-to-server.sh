#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Sends the finished tree (publish-tree.sh) to the repository server in an order that keeps
# the repository consistent while it changes:
#   1. pool/            (new packages first: nothing refers to them yet)
#   2. by-hash files, then the Packages indexes
#   3. the key, the page, then Release, Release.gpg and, last of all, InRelease
#   4. deletions within the owned pool/ and dists/ trees
# It is a DRY RUN unless --go is given: it lists what each step would do.
#
# Usage: sync-to-server.sh DEST [--go]
# The target is the server in the local configuration (SPARKY_SYNC_HOST and SPARKY_SYNC_PATH,
# reached over ssh with SPARKY_SYNC_SSH_KEY; sparky-os/config/build.conf.example), or
# SPARKY_SYNC_TARGET when set (a local folder, for tests).
# Last update 2026/10/22
set -euo pipefail
GO=0
DEST=
for a in "$@"; do
	case $a in
	--go) GO=1 ;;
	-*) echo "unknown option $a" >&2; exit 2 ;;
	*) DEST=$a ;;
	esac
done
[ -n "$DEST" ] && [ -d "$DEST" ] || { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
DEST=$(cd "$DEST" && pwd)/
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../config/local-config.sh"
CODENAME=mashtabba
for need in pool "dists/$CODENAME/InRelease" "dists/$CODENAME/Release" "dists/$CODENAME/Release.gpg"; do
	[ -e "$DEST$need" ] || { echo "$DEST is not a finished tree: $need is missing" >&2; exit 1; }
done
# Recheck final archives even when the tree was assembled by another tool.
PYTHONPATH="$HERE/..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release check-repo "$DEST"
TARGET=${SPARKY_SYNC_TARGET:?set SPARKY_SYNC_TARGET in the local configuration}
case $TARGET in */) ;; *) TARGET=$TARGET/ ;; esac
OPTS=(-rltv --itemize-changes)
case $TARGET in
*:*) OPTS+=(-e "ssh -o IdentitiesOnly=yes -i ${SPARKY_SYNC_SSH_KEY:?set SPARKY_SYNC_SSH_KEY in the local configuration}") ;;
esac
if [ "$GO" = 1 ]; then echo "== LIVE run to $TARGET"; else OPTS+=(--dry-run); echo "== dry run to $TARGET (use --go to send)"; fi
R() { rsync "${OPTS[@]}" "$@"; }
BH="dists/$CODENAME/main/*/by-hash"

echo "-- 1. pool"
R --exclude='*.tmp' "${DEST}pool/" "${TARGET}pool/"
echo "-- 2. by-hash files, then the indexes"
R --relative --include="dists/" --include="dists/$CODENAME/" --include="dists/$CODENAME/main/" \
	--include="dists/$CODENAME/main/*/" --include="dists/$CODENAME/main/*/by-hash/***" \
	--exclude='*' "$DEST./" "$TARGET"
R --relative --include="dists/" --include="dists/$CODENAME/" --include="dists/$CODENAME/main/" \
	--include="dists/$CODENAME/main/*/" --include='Packages*' --include='Sources*' --exclude='*' "$DEST./" "$TARGET" \
	--exclude="$BH"
echo "-- 3. key, page, then Release, Release.gpg, InRelease"
R "${DEST}sparky-stereo-repo.asc" "${DEST}index.html" "$TARGET"
R "${DEST}dists/$CODENAME/Release" "${DEST}dists/$CODENAME/Release.gpg" "${TARGET}dists/$CODENAME/"
R "${DEST}dists/$CODENAME/InRelease" "${TARGET}dists/$CODENAME/"
echo "-- 4. deletions"
# Independently published development channels and fixtures share the web root.
# Own only these repository trees; never mirror/delete the entire server root.
R --delete --delete-after "${DEST}pool/" "${TARGET}pool/"
R --delete --delete-after "${DEST}dists/" "${TARGET}dists/"
[ "$GO" = 1 ] || echo "== dry run only; nothing was sent"
