#!/bin/sh
# Published-package negative controls on the AMD compositor with both GPUs.
set -eu
unset LD_LIBRARY_PATH QT_PLUGIN_PATH MLT_REPOSITORY MLT_DATA MLT_PROFILES_PATH __EGL_VENDOR_LIBRARY_FILENAMES MESA_LOADER_DRIVER_OVERRIDE DRI_PRIME
export WAYLAND_DISPLAY=order223-route
mkdir -p /w/final/published-controls
out=/w/final/published-controls
set +e
/w/device-choice > "$out/device-choice.log" 2>&1
code=$?
set -e
printf '%s\n' "$code" > "$out/device-choice.exit"
[ "$code" = 1 ]
export LD_PRELOAD=/w/probes/decoder-trace.so
for engine in mlt qt vlc; do
 export DECODER_TRACE=$out/$engine.trace
 if [ "$engine" = vlc ]; then
  LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/vlc-stereo /w/probes/vlc-proof /prev/fixtures/h264-eyes8.mkv "$out/$engine.raw" 8 --avcodec-hw=any > "$out/$engine.log" 2>&1
 else
  /w/probes/$engine-proof /prev/fixtures/h264-eyes8.mkv "$out/$engine.raw" 8 48 > "$out/$engine.log" 2>&1
 fi
done
export DECODER_TRACE=$out/libmpv.trace
/w/probes/libmpv-proof /prev/fixtures/h264-eyes8.mkv > "$out/libmpv.log" 2>&1
unset LD_PRELOAD
/usr/bin/mpv --no-config --vo=null --ao=null --no-terminal --log-file="$out/mpv.log" /prev/fixtures/h264-eyes8.mkv
