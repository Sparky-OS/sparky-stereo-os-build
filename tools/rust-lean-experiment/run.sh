#!/bin/bash
set -euo pipefail
export LC_ALL=C
ulimit -c 0
for tool in python3 flock nohup readlink; do
    command -v "$tool" >/dev/null || { echo "Required host tool missing: $tool" >&2; exit 1; }
done
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
mkdir -p runtime
# A live worker owns the lock. Re-running this command reports it without clearing pause.
if flock -n -E 75 runtime/worker.lock true; then
    :
else
    result=$?
    if [ "$result" = 75 ]; then exec ./status.sh; fi
    echo "Worker lock probe failed: exit $result" >&2
    exit "$result"
fi
rm -f pause.request
nohup python3 scripts/runner.py worker "$PWD" >> runtime/worker.log 2>&1 < /dev/null &
echo "Worker started as PID $!; ./status.sh reads state, ./pause.sh requests a pause after this step."
