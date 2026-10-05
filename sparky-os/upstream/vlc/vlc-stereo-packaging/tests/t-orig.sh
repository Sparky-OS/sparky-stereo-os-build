#!/bin/bash
# the original VLC: version, help and a capture of the end of a clip (paused on the last frame area): the same before and after VLC Stereo is installed
export HOME=/tmp/oh LANG=C.UTF-8 DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1; rm -rf $HOME; mkdir -p $HOME
echo "version: $(vlc --version 2>&1 | head -n 1 | md5sum | cut -c1-12)  help: $(vlc --help 2>&1 | md5sum | cut -c1-12)  longhelp: $(vlc --advanced --full-help 2>&1 | md5sum | cut -c1-12)"
echo "plugins: $(vlc --list 2>/dev/null | md5sum | cut -c1-12)"
Xvfb :99 -screen 0 1400x900x24 >/dev/null 2>&1 &
sleep 2
for c in clips/2d.mp4 clips/x264-2d.mp4; do
  vlc -I dummy --no-audio --avcodec-hw=none --no-video-title-show --start-time=2 --play-and-pause /w/run/$c >/dev/null 2>&1 &
  vp=$!; sleep 9
  import -window root /tmp/cap.png 2>/dev/null
  echo "$c capture md5: $(convert /tmp/cap.png -depth 8 rgb:- | md5sum | cut -c1-16)"
  kill $vp 2>/dev/null; sleep 1; kill -9 $vp 2>/dev/null
done
