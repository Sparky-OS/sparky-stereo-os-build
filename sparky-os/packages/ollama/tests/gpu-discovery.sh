#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# The engine with no model in a container that has a graphics card (NVIDIA through CDI): which back ends find it.
# No model is pulled, loaded or run. Usage: gpu-discovery.sh EXPECTED-LIBRARY...  (CUDA, Vulkan, ROCm, as the engine names them)
set -u
fail=0
export HOME=$(mktemp -d)
unit=/usr/lib/systemd/user/ollama.service
mapfile -t envs < <(sed -n 's/^Environment=//p' "$unit")
env "${envs[@]}" OLLAMA_DEBUG=1 /usr/bin/ollama serve > "$HOME/serve.log" 2>&1 &
pid=$!
for _ in $(seq 1 120); do grep -q 'inference compute\|no compatible GPUs' "$HOME/serve.log" && break; sleep 0.5; done
sleep 2
kill "$pid"; wait "$pid" 2>/dev/null
grep -E 'inference compute|no compatible GPUs|unable to load|failed to load|error' "$HOME/serve.log" | cut -c1-300 | head -12
for lib in "$@"; do
	if grep -E 'inference compute' "$HOME/serve.log" | grep -q "library=$lib"; then echo "PASS the engine finds a card through $lib"; else echo "FAIL no card through $lib"; fail=1; fi
done
exit $fail
