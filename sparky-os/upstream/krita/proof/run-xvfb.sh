#!/bin/sh
# usage: run-xvfb.sh <outbase> <prefix> <file>   Krita on Xvfb with a 30-bit root (software GL)
export XDG_RUNTIME_DIR=/tmp/rt; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; export HOME=/w/khome; mkdir -p $HOME/.config
out=$1; P=$2; file=$3
Xvfb :77 -screen 0 1280x800x${DEPTH:-30} +extension GLX >/tmp/xvfb.log 2>&1 &
sleep 3
export DISPLAY=:77 LIBGL_ALWAYS_SOFTWARE=1
unset WAYLAND_DISPLAY
rm -f $HOME/.config/kritadisplayrc
xdpyinfo | grep -E "depth of root|depths"
export RB_OUT=$out LD_PRELOAD="/w/t/rbshim.so"
export LD_LIBRARY_PATH=/w/prefix/$P/lib/x86_64-linux-gnu XDG_DATA_DIRS=/w/prefix/$P/share:/usr/share QML2_IMPORT_PATH=/w/prefix/$P/lib/x86_64-linux-gnu/qml QT_LOGGING_RULES="krita.opengl=true"
/w/prefix/$P/bin/krita "$file" >$out.client.log 2>&1 &
cpid=$!
sleep ${WAIT:-60}
touch /tmp/rb.trigger; sleep 3
kill $cpid; sleep 1; pkill Xvfb
python3 /w/t/analyze.py $out 2>&1 | tail -8
