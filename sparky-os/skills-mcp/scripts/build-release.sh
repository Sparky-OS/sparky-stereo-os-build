#!/bin/bash
# Builds the engine program static (musl, ReleaseSmall) with the station's cgm-zig and stages it as the package will carry it:
#   $OUT/stage/usr/libexec/sparky-stereo-skills/engine  and  $OUT/stage/SHA256SUMS
# The bash helper /usr/bin/sparky-stereo-skills execs it for find|list|context|sections|read|manifest|commands|run|serve|mcp.
# Packaging that stage into a .deb (a new architecture-specific package, the Lean Code gate, the signed stage) is the
# package recipe's job, not this script's.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:?Set OUT to the scratch directory}
export ZIG_GLOBAL_CACHE_DIR=$OUT/zig-global ZIG_LOCAL_CACHE_DIR=$OUT/zig-cache-release
rm -rf "$OUT/stage" "$OUT/release-prefix"
(cd "$HERE" && zig build -Doptimize=ReleaseSmall --prefix "$OUT/release-prefix")
install -Dm755 "$OUT/release-prefix/bin/sparky-stereo-skills" "$OUT/stage/usr/libexec/sparky-stereo-skills/engine"
(cd "$OUT/stage" && find usr -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum >SHA256SUMS)
rm -rf "$ZIG_LOCAL_CACHE_DIR"
cat "$OUT/stage/SHA256SUMS"
