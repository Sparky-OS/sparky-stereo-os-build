#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Rebuild a copied standalone descriptor, preserve exact payloads, retain receipts.
set -euo pipefail
recipe=${1:?recipe directory}
descriptor=${2:?copied descriptor}
image=${3:?immutable local builder image}
name=${4:?container name}
build_tree=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
output=$(dirname "$(readlink -f "$descriptor")")
. "$build_tree/sparky-os/repo/build-provenance.sh"
unset SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
sparky_provenance_init "$image" "$recipe"
docker run --rm --pull=never --name "$name" --platform linux/amd64 --ulimit core=0 --cpus 4 --network none \
  --user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" \
  -e HOME=/tmp -e PYTHONPATH=/toolkit \
  -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
  -v "$build_tree/sparky-os":/toolkit:ro -v "$output":/output \
  "$image" bash -euc 'ulimit -c 0; python3 /toolkit/repo/rebuild-script-source.py "/output/$1"; python3 -m lean.release check-debs /output/*.deb' \
  bash "$(basename "$descriptor")"
