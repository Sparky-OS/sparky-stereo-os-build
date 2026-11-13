#!/bin/bash
set -euo pipefail
export LC_ALL=C
ulimit -c 0
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
mkdir -p runtime
# A live worker owns the lock. Re-running this command reports it without clearing pause.
if ! flock -n runtime/worker.lock true; then
    exec ./status.sh
fi
rm -f pause.request
nohup python3 scripts/runner.py worker "$PWD" >> runtime/worker.log 2>&1 < /dev/null &
echo "Worker started as PID $!; ./status.sh reads state, ./pause.sh requests a pause after this step."
