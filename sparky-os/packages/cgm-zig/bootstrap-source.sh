#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
set -euo pipefail
SOURCE=${1:?Usage: bootstrap-source.sh EXTRACTED_SOURCE}
cd "$SOURCE"
export PYTHONPATH="$SOURCE/debian/sparky-lean-toolkit"
export LEAN_ZIG="$SOURCE/build/zig2"
PLAN=debian/sparky-lean-languages.json
test ! -e build
test ! -e .sparky-lc
python3 - "$PLAN" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if json.loads(p.read_text()) != ['c', 'zig']:
    raise SystemExit('cgm-zig: expected retained C and Zig language plan')
p.rename(str(p) + '.bootstrap-save')
p.write_text('["c"]\n')
PY
trap 'mv "$PLAN.bootstrap-save" "$PLAN"' EXIT
# Qualify the native bootstrap inputs before a compiler exists for Zig.
python3 -m lean.source_tree project "$SOURCE"
bash debian/cgm/configure.sh "$SOURCE" "$SOURCE/build"
mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR" "$LEAN_ZIG_CACHE"
cmake --build build --target zig2 --parallel 4
test "$("$LEAN_ZIG" version)" = 0.16.0+cgm.0399d2b19b
# Keep the first pass receipt, restore exact authored inputs, then qualify
# both languages using the same compiler that will build stage3.
python3 -m lean.source_tree restore "$SOURCE"
mv .sparky-lc build/bootstrap-projection
mv "$PLAN.bootstrap-save" "$PLAN"
trap - EXIT
python3 -m lean.source_tree project "$SOURCE"
