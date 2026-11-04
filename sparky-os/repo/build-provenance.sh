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
# Usage: . build-provenance.sh; sparky_provenance_init IMAGE
SPARKY_PROV_ARGS=()
sparky_provenance_init() {
	local image=${1:?image} tree commit='' dirty=0 id='' digests='' invocation started why=()
	tree=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
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
		-e "SPARKY_BUILD_IMAGE_NAME=$image" -e "SPARKY_PROVENANCE_REQUIRED=${SPARKY_PROVENANCE_REQUIRED:-}")
	[ -z "$commit" ] || SPARKY_PROV_ARGS+=(-e "SPARKY_BUILD_COMMIT=$commit" -e "SPARKY_BUILD_DIRTY=$dirty")
	[ -z "$id" ] || SPARKY_PROV_ARGS+=(-e "SPARKY_BUILD_IMAGE_ID=$id" -e "SPARKY_BUILD_IMAGE_REPO_DIGESTS=$digests")
}
