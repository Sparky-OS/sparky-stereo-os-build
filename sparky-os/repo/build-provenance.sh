#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# The facts of a package build that only the host knows, passed into the build container (ORDER 394b).
# A build script sources this file and, right before its `docker run`, calls
#     sparky_provenance_init IMAGE
# then adds "${SPARKY_PROV_ARGS[@]}" to the docker run line. The container's `lean.release check-debs` writes the build
# record beside the .deb files from these values (sparky-os/lean/buildrecord.py); make-provenance.py reads it.
# Facts: the build repository's commit (and whether sparky-os differs from it), the image's id, an invocation id,
# the moment the script started. A fact that cannot be read is said on stderr and left out; the record then lists it
# as unrecorded and the statement reports the gap. SPARKY_PROVENANCE_REQUIRED=1 stops the script instead.
# ORDER 421b: the same call gives the build its source date. The date of a source package belongs to its recipe, never to
# the clock (repo/reproducible.py, ORDER 421): SOURCE_DATE_EPOCH as the caller set it, else the committer date of the last
# commit touching the calling script's folder (a clean tree is required). The call then exports SOURCE_DATE_EPOCH and
# SOURCE_DATE_RFC2822 (the changelog trailer date, UTC), and SPARKY_PROV_ARGS carries both into the container with
# reproducible.py mounted at /run/reproducible.py (inner scripts normalize debian/ with it before dpkg-source -b).
# There is no clock fallback: a recipe with no date stops the call (return 1) and says why and what to set.
# Usage: . build-provenance.sh; sparky_provenance_init IMAGE [RECIPE_DIR]   (RECIPE_DIR defaults to the caller script's folder)
SPARKY_PROV_ARGS=()
sparky_provenance_init() {
	local image=${1:?image} tree commit='' dirty=0 id='' digests='' invocation started why=() recipe basis date_error
	tree=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
	recipe=${2:-$(dirname "${BASH_SOURCE[1]}")}
	if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
		basis=${SPARKY_SOURCE_DATE_BASIS:-environment}      # a caller that took the date from somewhere else says where
	else
		basis="the last commit touching ${recipe#"$tree"/}"
	fi
	if ! SOURCE_DATE_EPOCH=$(python3 "$tree/sparky-os/repo/reproducible.py" epoch "$recipe") ||
			! SOURCE_DATE_RFC2822=$(python3 "$tree/sparky-os/repo/reproducible.py" rfc2822 "$SOURCE_DATE_EPOCH"); then
		echo "provenance: no source date for $recipe, stopping (see above)" >&2
		return 1
	fi
	export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
	if commit=$(git -C "$tree" rev-parse --verify HEAD 2>/dev/null) && [ "${#commit}" = 40 ]; then
		[ -z "$(git -C "$tree" status --porcelain --untracked-files=normal -- sparky-os 2>/dev/null)" ] || dirty=1
	else
		commit=''; why+=("$tree is not a git checkout with a commit")
	fi
	if id=$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null) && [[ $id =~ ^sha256:[0-9a-f]{64}$ ]]; then
		digests=$(docker image inspect --format '{{range .RepoDigests}}{{.}} {{end}}' "$image" 2>/dev/null || true)
	else
		id=''; why+=("docker image inspect $image gave no id")
	fi
	invocation=$(cat /proc/sys/kernel/random/uuid)
	started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	if [ "${#why[@]}" -gt 0 ]; then
		printf 'provenance: NOT recorded: %s\n' "${why[@]}" >&2
		if [ "${SPARKY_PROVENANCE_REQUIRED:-}" = 1 ]; then
			echo "provenance: SPARKY_PROVENANCE_REQUIRED=1, stopping" >&2
			return 1
		fi
	fi
	SPARKY_PROV_ARGS=(-e "SPARKY_BUILD_INVOCATION=$invocation" -e "SPARKY_BUILD_STARTED=$started"
		-e "SPARKY_BUILD_IMAGE_NAME=$image" -e "SPARKY_PROVENANCE_REQUIRED=${SPARKY_PROVENANCE_REQUIRED:-}"
		-e "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH" -e "SOURCE_DATE_RFC2822=$SOURCE_DATE_RFC2822" -e "SPARKY_SOURCE_DATE_BASIS=$basis"
		--mount "type=bind,src=$tree/sparky-os/repo/reproducible.py,dst=/run/reproducible.py,readonly")
	[ -z "$commit" ] || SPARKY_PROV_ARGS+=(-e "SPARKY_BUILD_COMMIT=$commit" -e "SPARKY_BUILD_DIRTY=$dirty")
	[ -z "$id" ] || SPARKY_PROV_ARGS+=(-e "SPARKY_BUILD_IMAGE_ID=$id" -e "SPARKY_BUILD_IMAGE_REPO_DIGESTS=$digests")
}
