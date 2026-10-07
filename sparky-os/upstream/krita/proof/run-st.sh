#!/bin/bash
# usage: run-st.sh <outbase> <prefix-name> <file>   env: KRC (kritadisplayrc content), WAIT, SW SH, KRITA_ARGS, KENV
# headless KWin (our build) + Xwayland, Krita from /w/prefix/<prefix> on Qt's xcb platform, capture of screen and window with the ScreenShot2 "stereo" key
out=$1; P=$2; file=$3
export XDG_RUNTIME_DIR=/tmp/rt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export HOME=/w/khome LANG=C.UTF-8 LC_ALL=C.UTF-8
mkdir -p $HOME/.config; rm -f $HOME/.config/kritadisplayrc
[ -n "$KRC" ] && printf '%s\n' "$KRC" > $HOME/.config/kritadisplayrc
exec dbus-run-session -- bash -c '
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 QT_LOGGING_RULES="kwin_scripting.debug=true" kwin_wayland --virtual --xwayland --socket=sub --width '${SW:-1280}' --height '${SH:-800}' > '$out'.kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/sub && break; sleep .25; done
sleep 2
unset WAYLAND_DISPLAY; export DISPLAY=:0 QT_QPA_PLATFORM=xcb
export LD_LIBRARY_PATH=/w/prefix/'$P'/lib/x86_64-linux-gnu XDG_DATA_DIRS=/w/prefix/'$P'/share:/usr/share QML2_IMPORT_PATH=/w/prefix/'$P'/lib/x86_64-linux-gnu/qml
env $KENV /w/prefix/'$P'/bin/krita '${KRITA_ARGS:-}' '$file' > '$out'.client.log 2>&1 &
cp=$!
for t in 8 16 24 32 40; do sleep 8; for w in $(xwininfo -root -tree 2>/dev/null | grep -i "krita" | awk "{print \$1}"); do echo "t=$t $w $(xwininfo -id $w | grep -E "Width|Height" | tr "\n" " ")" >> '$out'.geom.txt; done; done; sleep '${WAIT:-50}'
id=$(dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript string:/w/t/nudge.js string:nudge 2>/dev/null | awk "/int32/{print \$2}")
dbus-send --session --dest=org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run 2>/dev/null
id2=$(dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript string:/w/t/geom.js string:geom 2>/dev/null | awk "/int32/{print \$2}"); dbus-send --session --dest=org.kde.KWin /Scripting/Script$id2 org.kde.kwin.Script.run 2>/dev/null; sleep 6
/w/t/capture screen '$out'.screen.png > '$out'.capture.txt 2>&1
/w/t/capture window '$out'.window.png >> '$out'.capture.txt 2>&1
xprop -root _KDE_NET_WM_STEREO_CONTENT >> '$out'.capture.txt 2>&1
for w in $(xwininfo -root -tree 2>/dev/null | grep -i krita | awk "{print \$1}"); do echo "win $w: $(xprop -id $w _KDE_NET_WM_STEREO_CONTENT 2>&1) $(xwininfo -id $w | grep -E "Width|Height" | tr "\n" " ")" >> '$out'.capture.txt; done
kill $cp 2>/dev/null; sleep 2; kill $kp; wait $kp 2>/dev/null
exit 0
'
