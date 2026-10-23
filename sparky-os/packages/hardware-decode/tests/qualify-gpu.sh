#!/bin/sh
# In a disposable GPU container; /w is an owned workspace and /kit this test tree.
set -eu
: "${GPU:?amd or nvidia}" "${API:?vaapi or cuda}"
export LD_LIBRARY_PATH=/w/ffmpeg-build/libavcodec${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
for script in final-run-mpv final-run-engines final-run-cancellation-recorded additional-codecs references mpv-images final-run-vlc vlc-vmem-matrix; do
 sh /kit/tests/$script.sh
done
