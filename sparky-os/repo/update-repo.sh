#!/bin/bash
#
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Adds staged packages to the local development repository and reindexes it.
# Each STAGED folder holds .deb files (dbgsym packages are left out), optionally the source
# package (.dsc and the files it names) and a SHA256SUMS that covers them; it is checked first.
# For every new binary the other versions of the same package and architecture move to
# SPARKY_REPO_SUPERSEDED, the new one is copied in, the sources go to source/, and then
# make-repo.sh reindexes (it applies the provenance fields to every package first).
# Nothing already in the repository is overwritten.
#
# Usage: update-repo.sh [--dry-run] STAGED...
# A relative STAGED folder is looked up in SPARKY_STAGING_DIR.
# Settings: SPARKY_REPO_DIR, SPARKY_REPO_SUPERSEDED, SPARKY_STAGING_DIR (sparky-os/config/build.conf.example).
# Last update 2026/10/22
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../config/local-config.sh"
sparky_need SPARKY_REPO_DIR SPARKY_REPO_SUPERSEDED
DRY=0
STAGED=()
for a in "$@"; do
	case $a in
	--dry-run) DRY=1 ;;
	-*) echo "unknown option $a" >&2; exit 2 ;;
	*) STAGED+=("$a") ;;
	esac
done
[ ${#STAGED[@]} -gt 0 ] || { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
R=$SPARKY_REPO_DIR
S=$SPARKY_REPO_SUPERSEDED
[ -d "$R/source" ] || { echo "$R is not a development repository (no source/)" >&2; exit 1; }
do_() { if [ "$DRY" = 1 ]; then echo "would: $*"; else "$@"; fi; }
exec 9>"$(dirname "$R")/.update-repo.lock"
flock -n 9 || { echo "another repository update is running" >&2; exit 1; }
cd "$R"
PACKAGES=()
for O in "${STAGED[@]}"; do
	case $O in /*) ;; *) sparky_need SPARKY_STAGING_DIR; O=$SPARKY_STAGING_DIR/$O ;; esac
	[ -f "$O/SHA256SUMS" ] || { echo "$O has no SHA256SUMS" >&2; exit 1; }
	(cd "$O" && sha256sum -c --quiet SHA256SUMS)
	for b in $(ls "$O"/*.deb 2>/dev/null | sort -V); do
		case $b in *-dbgsym_*) continue ;; esac
		f=$(basename "$b"); p=${f%%_*}; a=${f##*_}
		for old in "${p}"_*_"$a"; do [ "$old" != "$f" ] && [ -f "$old" ] && do_ mv -n "$old" "$S/"; done
		do_ cp -n "$b" .
		PACKAGES+=("$p")
	done
	for s in "$O"/*.dsc "$O"/*.debian.tar.* "$O"/*.orig.tar.* "$O"/*.tar.xz "$O"/*.tar.gz; do
		[ -f "$s" ] && do_ cp -n "$s" source/
	done
done
[ ${#PACKAGES[@]} -gt 0 ] || { echo "no packages staged" >&2; exit 1; }
if [ "$DRY" = 1 ]; then
	echo "would: $HERE/make-repo.sh $R"
	exit 0
fi
"$HERE/make-repo.sh" "$R" >/dev/null 2>&1
sync
for p in $(printf '%s\n' "${PACKAGES[@]}" | sort -u); do
	awk -v p="$p" '$0=="Package: "p{f=1} f&&/^Version:/{print p, $2; exit}' "$R/Packages"
done
