#!/bin/sh
set -eu
unset __EGL_VENDOR_LIBRARY_FILENAMES MESA_LOADER_DRIVER_OVERRIDE DRI_PRIME QT_PLUGIN_PATH
export WAYLAND_DISPLAY=order223-route
export LD_LIBRARY_PATH=/prev/mlt-build/out/lib:/prev/ffmpeg-build/libavcodec:/usr/lib/x86_64-linux-gnu/vlc-stereo
export LD_PRELOAD=/prev/decoder-trace.so
export MLT_REPOSITORY=/prev/mlt-build/out/lib/mlt MLT_DATA=/usr/share/mlt-7 MLT_PROFILES_PATH=/usr/share/mlt-7/profiles
mkdir -p /w/final/$SCENARIO
for engine in mlt qt vlc; do
 export DECODER_TRACE=/w/final/$SCENARIO/$engine.trace
 case $engine in
 mlt) /prev/mlt-proof /prev/fixtures/h264-eyes8.mkv /w/final/$SCENARIO/mlt.raw 8 48 > /w/final/$SCENARIO/mlt.log 2>&1 ;;
 qt) /prev/qt-proof /prev/fixtures/h264-eyes8.mkv /w/final/$SCENARIO/qt.raw 8 48 > /w/final/$SCENARIO/qt.log 2>&1 ;;
 vlc) /prev/vlc-proof /prev/fixtures/h264-eyes8.mkv /w/final/$SCENARIO/vlc.raw 8 --avcodec-hw=any > /w/final/$SCENARIO/vlc.log 2>&1 ;;
 esac
done
python3 - <<'PY'
import csv,os,pathlib
base=pathlib.Path('/w/final')/os.environ['SCENARIO']
for engine in ('mlt','qt','vlc'):
 rows=list(csv.reader((base/(engine+'.trace')).read_text().splitlines()))
 assert rows
 status=0 if all(r[2]=='vaapi' for r in rows) else 1
 (base/(engine+'-route.exit')).write_text(str(status)+'\n')
 assert status==1,(engine,rows[0])
 print(engine,'old default fails expected display VAAPI route:',rows[0][2])
PY
