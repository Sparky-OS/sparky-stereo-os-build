#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# The engine with no model, as an ordinary user, in a container with no network: the service's own ExecStart and Environment
# lines (read from the installed unit), the binding, the origins mail add-ons need, and a model download refused with its cause.
# No model is pulled, loaded or run. Exit 0 when every check passes.
set -u
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
unit=/usr/lib/systemd/user/ollama.service
# The unit's [Service] lines, as systemd reads them (simple KEY=VALUE, no quoting in this unit)
exe=$(sed -n 's/^ExecStart=//p' "$unit")
mapfile -t envs < <(sed -n 's/^Environment=//p' "$unit")
echo "ExecStart: $exe"; printf 'Environment: %s\n' "${envs[@]}"
export HOME=$(mktemp -d)
env "${envs[@]}" $exe > "$HOME/serve.log" 2>&1 &
pid=$!
for _ in $(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:11434/api/version && break; sleep 0.5; done
echo "version: $(curl -s http://127.0.0.1:11434/api/version)"
listeners=$(ss -Htln 2>/dev/null | awk '{print $4}' | sort -u | tr '\n' ' ')
echo "listening: $listeners"
check 'listens on 127.0.0.1:11434' '[[ " $listeners " == *" 127.0.0.1:11434 "* ]]'
check 'listens on nothing else' '[ "$(echo $listeners | wc -w)" = 1 ]'
check 'no model in the store' '[ "$(curl -s http://127.0.0.1:11434/api/tags)" = "{\"models\":[]}" ]'
acao=$(curl -s -D - -o /dev/null -H 'Origin: moz-extension://0a1b2c3d-test' http://127.0.0.1:11434/api/tags | tr -d '\r' | sed -n 's/^[Aa]ccess-[Cc]ontrol-[Aa]llow-[Oo]rigin: //p')
echo "a mail add-on's origin gets: Access-Control-Allow-Origin: ${acao:-(none)}"
check 'a moz-extension:// origin is allowed' '[ "$acao" = "moz-extension://0a1b2c3d-test" ]'
other=$(curl -s -D - -o /dev/null -H 'Origin: https://example.org' http://127.0.0.1:11434/api/tags | tr -d '\r' | head -1)
echo "a web page's origin (https://example.org) gets: $other"
check 'a web page origin is refused' '[[ "$other" == *" 403"* ]]'
pull=$(curl -s -m 20 -X POST -d '{"model":"qwen3.5:0.8b","stream":false}' http://127.0.0.1:11434/api/pull)
echo "a model download with no network: $pull"
check 'the download is refused with its cause' '[[ "$pull" == *error* ]]'
check 'still no model' '[ "$(curl -s http://127.0.0.1:11434/api/tags)" = "{\"models\":[]}" ]'
kill "$pid"; wait "$pid" 2>/dev/null
echo "== the engine's own log (discovery and library path)"
grep -E 'Listening on|library|inference compute|no compatible|total_vram|OLLAMA_ORIGINS' "$HOME/serve.log" | cut -c1-260 | head -12
exit $fail
