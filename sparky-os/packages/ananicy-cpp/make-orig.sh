#!/bin/bash
# Makes the orig archive of ananicy-cpp from the upstream clone in the build tree, byte for byte the same each time:
# git archive of the commit the recipe names (its time is the archive's time), one xz thread.
# Usage: make-orig.sh UPSTREAM_CLONE OUTDIR
set -euo pipefail
CLONE=${1:?the ananicy-cpp clone (sparky-os/upstream/ananicy-cpp)}; OUT=${2:?output folder}
COMMIT=3554447c1ca495478bd00e002078847dfd2205d6
[ "$(git -C "$CLONE" rev-parse --verify "$COMMIT^{commit}")" = "$COMMIT" ]
mkdir -p "$OUT"
git -C "$CLONE" archive --format=tar --prefix=ananicy-cpp-1.2.0+git20260818/ "$COMMIT" | xz -9e -T1 >"$OUT/ananicy-cpp_1.2.0+git20260818.orig.tar.xz"
sha256sum "$OUT/ananicy-cpp_1.2.0+git20260818.orig.tar.xz"
