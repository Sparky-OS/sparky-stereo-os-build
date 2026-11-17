#!/bin/bash
# Makes the orig archive of cachyos-ananicy-rules from CachyOS/ananicy-rules at the tag 1.1.49 (the tag CachyOS's cachyos-ananicy-rules PKGBUILD,
# CachyOS-PKGBUILDS 0c7ddbc13573, packages), byte for byte the same each time: git archive of the commit (its time is the archive's), one xz thread.
# The tag is a plain tag of the commit below; the commit is checked before anything is archived.
# Usage: make-orig.sh OUTDIR [CLONE]   (CLONE: an existing clone of the upstream at that tag; without it a shallow clone is made in a temporary folder)
set -euo pipefail
OUT=${1:?output folder}; COMMIT=03ef03fbf7e834385377432ccecaedd32e3414bb
CLONE=${2:-}
if [ -z "$CLONE" ]; then CLONE=$(mktemp -d); trap 'rm -rf "$CLONE"' EXIT; git clone -q --depth 1 --branch 1.1.49 https://github.com/CachyOS/ananicy-rules.git "$CLONE"; fi
[ "$(git -C "$CLONE" rev-parse --verify "$COMMIT^{commit}")" = "$COMMIT" ]
mkdir -p "$OUT"
git -C "$CLONE" archive --format=tar --prefix=cachyos-ananicy-rules-1.1.49/ "$COMMIT" | xz -9e -T1 >"$OUT/cachyos-ananicy-rules_1.1.49.orig.tar.xz"
sha256sum "$OUT/cachyos-ananicy-rules_1.1.49.orig.tar.xz"
