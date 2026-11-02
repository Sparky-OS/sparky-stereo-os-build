#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/source.env"
VERIFY=0
if [ "${1:-}" = --verify ]; then
	VERIFY=1
	shift
fi
DEST=${1:?Usage: fetch-source.sh [--verify] DESTINATION}
if [ "$VERIFY" = 0 ]; then
	if [ -e "$DEST" ] || [ -L "$DEST" ]; then
		printf 'cgm-zig: destination already exists: %s\n' "$DEST" >&2
		exit 1
	fi
	git clone -- "$CGM_ZIG_REPOSITORY" "$DEST"
fi
test "$(git -C "$DEST" remote get-url origin)" = "$CGM_ZIG_REPOSITORY"
git -C "$DEST" cat-file -e "$CGM_ZIG_COMMIT^{commit}"
git -C "$DEST" merge-base --is-ancestor "$CGM_ZIG_COMMIT" origin/main
if [ "$VERIFY" = 0 ]; then
	git -C "$DEST" checkout --detach "$CGM_ZIG_COMMIT"
fi
test "$(git -C "$DEST" rev-parse HEAD)" = "$CGM_ZIG_COMMIT"
test "$(git -C "$DEST" rev-parse --is-shallow-repository)" = false
test -z "$(git -C "$DEST" status --porcelain)"
printf 'cgm-zig: source %s checked out; expected compiler version %s\n' "$CGM_ZIG_COMMIT" "$CGM_ZIG_VERSION"
