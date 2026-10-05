#!/bin/bash
# subtitle (SRT), marquee text and the volume OSD, captured; usage via vlc-test.sh: vlc-osd.sh <clip> -- <vlc args>
. /w/run/common.sh
clip=$1; shift; [ "$1" = "--" ] && shift
mkdir -p $OUT
${VBIN:-/usr/bin/vlc-stereo} -I dummy --no-plugins-cache -vv --no-audio ${HW:---avcodec-hw=none} --no-video-title-show --repeat --vout=gl \
  --sub-file=/w/run/clips/osd.srt --sub-source=marq --marq-marquee=OSD-TEXT --marq-position=0 --marq-size=48 --marq-color=16777215 "$@" /w/run/clips/$clip > $OUT/vlc.log 2>&1 &
vp=$!
sleep 8
props > $OUT/props.txt
cap a; sleep 0.5
xdotool search --class vlc-stereo 2>/dev/null | head -n 1 | xargs -I{} xdotool windowactivate {} 2>/dev/null; sleep 1
xdotool key Up Up Up; sleep 0.4
cap b
kill $vp; sleep 1; kill -9 $vp 2>/dev/null
