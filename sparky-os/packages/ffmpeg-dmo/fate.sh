#!/bin/bash
# Usage: fate.sh BUILD OUT [SAMPLES]. Without SAMPLES, run all sample-free FATE.
# Preserve the exit status and totals even when an external sample is absent.
set -euo pipefail
tree=$(realpath "$1") out=$(realpath -m "$2")
mkdir -p "$out"
cd "$tree"
export LC_ALL=C
export LD_LIBRARY_PATH="$tree/libavcodec:$tree/libavdevice:$tree/libavfilter:$tree/libavformat:$tree/libavutil:$tree/libswresample:$tree/libswscale"
args=()
[ "$#" -lt 3 ] || args=("SAMPLES=$(realpath "$3")")
gcc --version > "$out/compiler.txt"
make "${args[@]}" fate-list > "$out/targets.txt"
set +e
make -k -j4 THREADS=1 "${args[@]}" fate > "$out/fate.log" 2>&1
status=$?
set -e
echo "$status" > "$out/exit"
python3 - "$tree" "$out" <<'PY'
import json
from pathlib import Path
import sys
tree, out = map(Path, sys.argv[1:])
targets = [line for line in (out / 'targets.txt').read_text().splitlines()
           if line.startswith('fate-')]
records = []
for target in targets:
    rep = tree / 'tests/data/fate' / (target.removeprefix('fate-') + '.rep')
    if rep.exists():
        fields = rep.read_text().split(':')
        records.append({'target': target, 'status': fields[1]})
(out / 'totals.json').write_text(json.dumps({
    'listed': len(targets), 'executed': len(records),
    'passed': sum(r['status'] == '0' for r in records),
    'failed': [r for r in records if r['status'] != '0'],
    'exit': int((out / 'exit').read_text()),
}, indent=2) + '\n')
PY
cat "$out/totals.json"
exit "$status"
