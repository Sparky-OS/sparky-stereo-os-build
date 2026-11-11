#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# Sends a round's bill of materials and provenance (round-supply-chain.sh's OUT/publish, signed by the main session) to the
# repository server, after the repository itself is live. It owns only sbom/ROUND/ and the symlink sbom/latest: it never
# touches pool/, dists/ or an earlier round's folder, and it deletes nothing outside sbom/ROUND/.
#   1. the documents (sbom/ROUND/)       2. SHA256SUMS and then SHA256SUMS.asc   3. sbom/latest -> ROUND
# It is a DRY RUN unless --go is given. Before anything is sent it checks SHA256SUMS against the files; --go also
# requires SHA256SUMS.asc and verifies it against the repository key, so unsigned documents are never published.
#
# Usage: sync-supply-chain.sh PUBLISH ROUND KEY [--go]
#   PUBLISH  round-supply-chain.sh's OUT/publish, with SHA256SUMS.asc added by Part 2
#   ROUND    the round's name, e.g. r1103a
#   KEY      the repository's public key (sparky-stereo-repo.asc of the tree)
# The target is the one sync-to-server.sh uses (SPARKY_SYNC_TARGET, or SPARKY_SYNC_HOST and SPARKY_SYNC_PATH, with
# SPARKY_SYNC_SSH_KEY): a folder, or HOST:PATH of the web root.
# Last update 2026/11/04
set -euo pipefail
GO=0 ARGS=()
for a in "$@"; do
	case $a in
	--go) GO=1 ;;
	-*) echo "unknown option $a" >&2; exit 2 ;;
	*) ARGS+=("$a") ;;
	esac
done
[ "${#ARGS[@]}" -eq 3 ] || { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
PUBLISH=$(realpath "${ARGS[0]}") ROUND=${ARGS[1]} KEY=$(realpath "${ARGS[2]}")
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../config/local-config.sh"
[[ $ROUND =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad round name: $ROUND" >&2; exit 2; }
[ -f "$PUBLISH/SHA256SUMS" ] || { echo "$PUBLISH/SHA256SUMS is missing" >&2; exit 1; }
(cd "$PUBLISH" && sha256sum --check --quiet SHA256SUMS) || { echo "the files differ from SHA256SUMS: not sending" >&2; exit 1; }
FILES=$(cut -c67- "$PUBLISH/SHA256SUMS")
if [ -f "$PUBLISH/SHA256SUMS.asc" ]; then
	TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
	gpg --batch --no-default-keyring --keyring "$TMP/k.gpg" --import "$KEY" >/dev/null 2>&1
	gpgv --keyring "$TMP/k.gpg" "$PUBLISH/SHA256SUMS.asc" "$PUBLISH/SHA256SUMS" 2>&1 | sed 's/^/gpgv: /'
	[ "${PIPESTATUS[0]}" = 0 ] || { echo "SHA256SUMS.asc does not verify against $KEY: not sending" >&2; exit 1; }
elif [ "$GO" = 1 ]; then
	echo "$PUBLISH/SHA256SUMS.asc is missing: sign SHA256SUMS first (Part 2); not sending unsigned documents" >&2
	exit 1
else
	echo "note: SHA256SUMS.asc is missing; --go would refuse"
fi
TARGET=${SPARKY_SYNC_TARGET:?set SPARKY_SYNC_TARGET in the local configuration}
case $TARGET in */) ;; *) TARGET=$TARGET/ ;; esac
OPTS=(-rltv --itemize-changes --mkpath)
case $TARGET in
*:*) OPTS+=(-e "ssh -o IdentitiesOnly=yes -i ${SPARKY_SYNC_SSH_KEY:?set SPARKY_SYNC_SSH_KEY in the local configuration}") ;;
esac
if [ "$GO" = 1 ]; then echo "== LIVE run to ${TARGET}sbom/$ROUND/"; else OPTS+=(--dry-run); echo "== dry run to ${TARGET}sbom/$ROUND/ (use --go to send)"; fi
R() { rsync "${OPTS[@]}" "$@"; }
echo "-- 1. the documents"
for f in $FILES; do R "$PUBLISH/$f" "${TARGET}sbom/$ROUND/"; done
echo "-- 2. SHA256SUMS, then its signature"
R "$PUBLISH/SHA256SUMS" "${TARGET}sbom/$ROUND/"
[ ! -f "$PUBLISH/SHA256SUMS.asc" ] || R "$PUBLISH/SHA256SUMS.asc" "${TARGET}sbom/$ROUND/"
echo "-- 3. sbom/latest -> $ROUND"
L=$(mktemp -d); trap 'rm -rf "${TMP:-}" "$L"' EXIT
ln -s "$ROUND" "$L/latest"
R "$L/latest" "${TARGET}sbom/"
[ "$GO" = 1 ] || echo "== dry run only; nothing was sent"
