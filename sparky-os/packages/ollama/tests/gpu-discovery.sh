#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/21
# The engine with no model, started by the service's own ExecStart and Environment lines (read from the installed unit), in a
# container that has graphics cards (NVIDIA through CDI, another card through its render node): which cards it computes on.
# CARD: the Partners choice written to [Render] Partners before the start (nothing written when it is not set: Automatic).
# Usage: [CARD=pci-0000:01:00.0|cpu|...] gpu-discovery.sh EXPECTED...   EXPECTED: LIBRARY@PCI (CUDA@0000:01:00.0,
# Vulkan@0000:0b:00.0) or cpu; exactly these, and nothing else, must be what the engine reports. No model is pulled, loaded or run.
set -u
fail=0
export HOME=$(mktemp -d)
export XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state
mkdir -p "$XDG_CONFIG_HOME"
if [ -n "${CARD:-}" ]; then printf '[Render]\nPartners=%s\n' "$CARD" > "$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"; fi
unit=/usr/lib/systemd/user/ollama.service
read -r -a exe < <(sed -n 's/^ExecStart=//p' "$unit")
mapfile -t envs < <(sed -n 's/^Environment=//p' "$unit")
env "${envs[@]}" OLLAMA_DEBUG=1 "${exe[@]}" > "$HOME/serve.log" 2>&1 &
pid=$!
for _ in $(seq 1 160); do grep -q 'inference compute\|no compatible GPUs' "$HOME/serve.log" && break; kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
sleep 2
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
echo "== Partners card: ${CARD:-Automatic}"
grep -E 'inference compute|no compatible GPUs|sparky-stereo-gpu|not in this computer|cannot run' "$HOME/serve.log" | sed -E 's/^time=[^ ]+ //' | cut -c1-300 | head -12
got=$(grep 'inference compute' "$HOME/serve.log" | sed -E 's/.* library=([^ ]+) .* pci_id=("[^"]*"|[^ ]*) .*/\1@\2/; s/"//g; s/^cpu@$/cpu/' | sort | tr '\n' ' ')
want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
if [ "$got" = "$want" ]; then echo "PASS the engine computes on exactly: $want"; else echo "FAIL the engine computes on: '$got', expected '$want'"; fail=1; fi
exit $fail
