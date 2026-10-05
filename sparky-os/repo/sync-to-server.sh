#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Sends the finished tree (publish-tree.sh) to the repository server in an order that keeps
# the repository consistent while it changes:
#   1. pool/            (new packages first: nothing refers to them yet)
#   2. by-hash files, then the Packages indexes
#   3. the key, the page, then Release, Release.gpg and, last of all, InRelease
#   4. deletions (old pool files, old by-hash files, anything the tree no longer has)
# It is a DRY RUN unless --go is given: it lists what each step would do.
#
# Usage: sync-to-server.sh DEST [--go]
# SPARKY_SYNC_TARGET overrides the target (a local folder, for tests); the default is
# the server named in the local configuration (SPARKY_SYNC_TARGET), over ssh.
# Last update 2026/10/05
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
SUITE=mashtabba
for need in pool "dists/$SUITE/InRelease" "dists/$SUITE/Release" "dists/$SUITE/Release.gpg"; do
	[ -e "$DEST$need" ] || { echo "$DEST is not a finished tree: $need is missing" >&2; exit 1; }
done
TARGET=${SPARKY_SYNC_TARGET:?set SPARKY_SYNC_TARGET in the local configuration}
case $TARGET in */) ;; *) TARGET=$TARGET/ ;; esac
OPTS=(-rltv --itemize-changes)
case $TARGET in
*:*) OPTS+=(-e "ssh -o IdentitiesOnly=yes -i ${SPARKY_SYNC_SSH_KEY:?set SPARKY_SYNC_SSH_KEY in the local configuration}") ;;
esac
if [ "$GO" = 1 ]; then echo "== LIVE run to $TARGET"; else OPTS+=(--dry-run); echo "== dry run to $TARGET (use --go to send)"; fi
R() { rsync "${OPTS[@]}" "$@"; }
BH="dists/$SUITE/main/binary-*/by-hash"

echo "-- 1. pool"
R --exclude='*.tmp' "${DEST}pool/" "${TARGET}pool/"
echo "-- 2. by-hash files, then the indexes"
R --relative --include="dists/" --include="dists/$SUITE/" --include="dists/$SUITE/main/" \
	--include="dists/$SUITE/main/binary-*/" --include="dists/$SUITE/main/binary-*/by-hash/***" \
	--exclude='*' "$DEST./" "$TARGET"
R --relative --include="dists/" --include="dists/$SUITE/" --include="dists/$SUITE/main/" \
	--include="dists/$SUITE/main/binary-*/" --include='Packages*' --exclude='*' "$DEST./" "$TARGET" \
	--exclude="$BH"
echo "-- 3. key, page, then Release, Release.gpg, InRelease"
R "${DEST}sparky-stereo-archive-keyring.gpg" "${DEST}sparky-stereo-archive-keyring.asc" "${DEST}index.html" "$TARGET"
R "${DEST}dists/$SUITE/Release" "${DEST}dists/$SUITE/Release.gpg" "${TARGET}dists/$SUITE/"
R "${DEST}dists/$SUITE/InRelease" "${TARGET}dists/$SUITE/"
echo "-- 4. deletions"
R --delete --delete-after "$DEST" "$TARGET"
[ "$GO" = 1 ] || echo "== dry run only; nothing was sent"
