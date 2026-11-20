#!/bin/bash
# Runs set-default-theme.sh on one script in a throwaway container, as a plain user, with no network (ORDER 718).
#   DOCKER_HOST=... IMAGE=debian:testing run.sh SCRIPT [TABLE]
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
script=$(readlink -f "$1")
table=${2:-}
image=${IMAGE:-debian:testing}
name=ptc718-run-$$
args=(--name "$name" --rm --pull=never --ulimit core=1 --network none --user "$(id -u):$(id -g)" --tmpfs /tmp:exec
	--mount "type=bind,source=$here/set-default-theme.sh,target=/t/set-default-theme.sh,readonly"
	--mount "type=bind,source=$script,target=/t/script,readonly")
[ -n "$table" ] && { : > "$table"; args+=(--mount "type=bind,source=$table,target=/t/table"); }
status=0
docker run "${args[@]}" "$image" bash /t/set-default-theme.sh /t/script ${table:+/t/table} || status=$?
exit $status
