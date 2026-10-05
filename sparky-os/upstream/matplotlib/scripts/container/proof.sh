# runs as uid 1000
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p $HOME $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export MESA_LOADER_DRIVER_OVERRIDE=
unset MESA_LOADER_DRIVER_OVERRIDE
cd /w
for spec in "$@"; do
  name=${spec%%:*}; rest=${spec#*:}; vid=${rest%%:*}; vo=${rest#*:}
  d=/w/evidence/playback/$name; mkdir -p $d; rm -f $d/*
  echo "== $name $vid $vo"
  timeout 120 dbus-run-session -- python3 scripts/run_playback_proof.py /pb/media/$vid $d/capture.png --evidence $d --vo $vo --check --frames /pb/media/frames
  echo "rc=$?"
done
