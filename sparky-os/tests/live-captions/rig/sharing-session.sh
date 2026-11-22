#!/bin/bash
set -euo pipefail
out=$1
mkdir -p "$out/shared" "$XDG_DATA_HOME/github.com.thewh1teagle.vibe"
printf 'LC73 path witness only. This is not a speech model.\n' > "$out/shared/ggml-lc73-path-witness.bin"
python3 - "$XDG_DATA_HOME/github.com.thewh1teagle.vibe/app_config.json" "$out/shared" <<'PY'
import json,sys
json.dump({'models_folder':sys.argv[2],'general.firstRun':False,'general.skippedSetup':True,'model.downloadPromptDismissed':True,'analytics_enabled':False,'dictation.enabled':False,'recording.meetingDetectionEnabled':False,'recording.shortcutEnabled':False,'tools.checkYtDlpUpdates':False},open(sys.argv[1],'w'))
PY
CAPTIOND_MODEL_PATH="$out/shared" captiond --engine stub --no-gpu --log-level debug > "$out/sharing-captiond.log" 2>&1 &
daemon_pid=$!
WEBKIT_INSPECTOR_SERVER=127.0.0.1:9222 RUST_LOG=debug strace -ff -e trace=openat,execve,network -o "$out/vibe.trace" vibe > "$out/vibe.log" 2>&1 &
vibe_pid=$!
cleanup() { kill "$vibe_pid" "$daemon_pid" 2>/dev/null || true; sleep 1; kill -KILL "$vibe_pid" "$daemon_pid" 2>/dev/null || true; wait "$vibe_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true; }
trap cleanup EXIT
sleep 12
captionctl list-models > "$out/captiond-model-list.txt"
sha256sum "$out/shared/ggml-lc73-path-witness.bin" > "$out/shared-file.sha256"
python3 /proof/atspi-tree.py > "$out/vibe-tree.json"
python3 /proof/capture.py "$out/vibe.png" > "$out/vibe-capture.json"
python3 /proof/mark_pns.py "$out/vibe.png" "$out/vibe.pns"
sleep 2
