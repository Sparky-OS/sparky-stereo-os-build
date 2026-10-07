#!/bin/bash
# Inside the container, as the user. Krita on native Wayland under headless KWin; captures of the window and the screen (ScreenShot2),
# the surfaces' readback (rbshim2, optional), the layer's log.
# env: INPUT (fakeinput commands, run before the captures), PFX (Krita prefix, empty: the installed package), FILE, KRC (kritadisplayrc content), WAIT, OUT (output base), SHIM=1, SW SH, KENV, KARGS, XCB=1
out=${OUT:?}
export HOME=/tmp/khome LANG=C.UTF-8 LC_ALL=C.UTF-8 XDG_RUNTIME_DIR=/tmp/rt-$$
mkdir -p $HOME/.config $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
[ -n "$KRC" ] && printf '%s\n' "$KRC" > $HOME/.config/kritadisplayrc
if [ -n "$PFX" ]; then
  export LD_LIBRARY_PATH=$PFX/lib/x86_64-linux-gnu XDG_DATA_DIRS=$PFX/share:/usr/share QML2_IMPORT_PATH=$PFX/lib/x86_64-linux-gnu/qml
  KRITA=$PFX/bin/krita
else
  KRITA=/usr/bin/krita
fi
if [ -n "$SHIM" ]; then
  [ -f /usr/local/lib/rbshim2.so ] && cp /usr/local/lib/rbshim2.so /tmp/rbshim2.so || gcc -shared -fPIC -O1 -o /tmp/rbshim2.so /k/t/rbshim2.c -ldl -lEGL -lGL -lX11 || exit 9
  export RB_OUT=$out LD_PRELOAD=/tmp/rbshim2.so
fi
exec dbus-run-session -- bash -c '
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 kwin_wayland --virtual --xwayland --socket=sub --width '${SW:-1280}' --height '${SH:-800}' > '$out'.kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/sub && break; sleep .25; done
sleep 2
export WAYLAND_DISPLAY=sub DISPLAY=:0
if [ -n "$XCB" ]; then unset WAYLAND_DISPLAY; export QT_QPA_PLATFORM=xcb; else export QT_QPA_PLATFORM=wayland; fi
export QT_LOGGING_RULES="${QLR:-krita.opengl=true}"
if [ -n "$PROG" ]; then env $KENV $PROG > '$out'.client.log 2>&1 & else env $KENV '$KRITA' --nosplash $KARGS '$FILE' > '$out'.client.log 2>&1 & fi
cp=$!
sleep '${WAIT:-45}'
tr "\0" "\n" < /proc/$cp/environ | grep -E "WAYLAND_DISABLE|QT_QPA_PLATFORM" > '$out'.env.txt
touch /tmp/rb.trigger
id=$(dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript string:/k/t/nudge.js string:nudge 2>/dev/null | awk "/int32/{print \$2}")
dbus-send --session --dest=org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run 2>/dev/null
sleep 8
[ -n "$INPUT" ] && /k/t/fakeinput $INPUT >> '$out'.input.log 2>&1
sleep 2
touch /tmp/rb.trigger
/k/t/capture screen '$out'.screen.png > '$out'.capture.txt 2>&1
/k/t/capture window '$out'.window.png >> '$out'.capture.txt 2>&1
sleep 1
kill -0 $cp 2>/dev/null && echo "client alive after capture" >> '$out'.capture.txt
kill $cp 2>/dev/null; sleep 2; kill $kp; wait $kp 2>/dev/null
exit 0
'
