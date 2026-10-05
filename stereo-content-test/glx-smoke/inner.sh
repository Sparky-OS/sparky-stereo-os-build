#!/bin/bash
export XDG_RUNTIME_DIR=/tmp/rt; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; export HOME=/home/t
kwin_wayland --virtual --xwayland --socket=g1 --width 1024 --height 640 > /tmp/kwin.log 2>&1 & kp=$!
for i in $(seq 1 80); do test -S $XDG_RUNTIME_DIR/g1 && break; sleep .25; done; sleep 2
export DISPLAY=:0
[ "$SMOKE_MODE" = software ] && export LIBGL_ALWAYS_SOFTWARE=1
echo "renderer: $(glxinfo -B 2>/dev/null | grep -m1 "OpenGL renderer" | cut -c1-70)"
echo "announce: $(xprop -root _KDE_NET_WM_STEREO_CONTENT_SUPPORTED 2>/dev/null)"
glxinfo 2>/dev/null | awk '/GLX Visuals/{v=1} /GLXFBConfigs/{v=0} v && /^0x/{n++; if($8=="y"&&$9!="y")m++; if($9=="y")s++} END{print "visuals",n,"| double-buffered mono",m+0,"| stereo",s+0}'
probe() {
  n=$1; shift
  (timeout 7 glxgears "$@" > /tmp/$n.log 2>&1 &); sleep 3
  w=$(xwininfo -root -tree 2>/dev/null | grep -m1 glxgears | awk '{print $1}')
  echo "$n: X window $(xwininfo -id $w 2>/dev/null | awk '/Width|Height/{printf "%s ", $2}')| declared: $(xprop -id $w _KDE_NET_WM_STEREO_CONTENT 2>/dev/null | sed 's/.*= //;s/.*not found.*/no/') | $(head -1 /tmp/$n.log | cut -c1-70)"
  sleep 5
}
probe mono-glxgears
probe stereo-glxgears -stereo
kill $kp
