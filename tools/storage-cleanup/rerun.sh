#!/bin/bash
set -euo pipefail

stage=${CLEANUP_FIXTURE_STAGE:?set the parent output directory}
ledger=${CLEANUP_FIXTURE_CONTAINER_IDS:?set the path for full container IDs}
prefix=${CLEANUP_FIXTURE_PREFIX:-storage-cleanup-fixture}
src=$(cd -- "$(dirname -- "$0")" && pwd)
: "${DOCKER_HOST:?set the isolated Docker socket}"
[[ $DOCKER_HOST == unix://* ]]
image=sha256:4590883a99c8623ceab9384525a425aa45d40c8a5b78a088eea148faede11551
out=${1:-$stage/fixture-$(date -u +%Y%m%dT%H%M%SZ)}
case "$out" in
    "$stage"/*) ;;
    *) printf '%s\n' 'Choose a new output directory under the lane stage.' >&2; exit 2 ;;
esac
[[ $(realpath -m -- "$out") == "$out" ]]
mkdir -- "$out"
name=
cleanup() {
    if [[ -n $name ]]; then
        docker rm -f "$name" >/dev/null
    fi
}
trap cleanup EXIT
run_case() {
    local label=$1 id
    shift
    name=$prefix-${label}-${BASHPID}
    id=$(docker create --name "$name" --platform linux/amd64 --network none --read-only \
        --user "$(id -u):$(id -g)" --cap-drop ALL --security-opt no-new-privileges \
        --ulimit core=1 --cpus 4 \
        --tmpfs "/fixture:rw,noexec,nosuid,nodev,size=16m,uid=$(id -u),gid=$(id -g),mode=0700" \
        --mount "type=bind,src=$src,dst=/src,readonly" \
        --mount "type=bind,src=$out,dst=/evidence" \
        "$@" "$image" python3 -B /src/fixture.py "$label")
    printf '%s\n' "$id" >> "$ledger"
    docker start -a "$name" > "$out/$label.log" 2>&1
    [[ $(docker inspect --format '{{.State.ExitCode}}' "$name") == 0 ]]
    docker rm "$name" >/dev/null
    name=
}
snapshot() {
    date -u
    cat /proc/loadavg
    df -B1 / "$stage" "$(dirname -- "$ledger")"
}
snapshot > "$out/start.txt"
trap 'snapshot > "$out/end.txt"; cleanup' EXIT
run_case measured
run_case foreign --tmpfs "/fixture/tmp/sparky-preview/sparky-preview-2222222222222222.tmp:rw,noexec,nosuid,nodev,size=1m,uid=$(id -u),gid=$(id -g),mode=0700"
run_case unmarked
printf '%s\n' "$out"
