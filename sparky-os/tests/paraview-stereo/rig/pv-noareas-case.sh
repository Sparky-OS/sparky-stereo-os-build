#!/bin/bash
# A desktop that shows no 3D areas: ParaView (default start, Enable 3D on) on a bare X server (Xvfb: no compositor, no
# stereo announced, so no stereo visual is offered), LANG as given. Captures the screen after the start, lists the X
# windows, and counts the told-once notices (windows named after ParaView's message box).
out=$1; mkdir -p $out
export HOME=$out/home XDG_RUNTIME_DIR=$(mktemp -d /tmp/rt.XXXXXX); mkdir -p $HOME/.config/ParaView; chmod 700 $XDG_RUNTIME_DIR
printf '{ "settings": { "GeneralSettings": { "AutoApply": 1 } } }\n' > $HOME/.config/ParaView/ParaView-UserSettings.json
printf '[General]\nGeneralSettings.ShowWelcomeDialog=0\n' > $HOME/.config/ParaView/ParaView.ini
Xvfb :7 -screen 0 1920x1080x24 -nolisten tcp > $out/xvfb.log 2>&1 & xp=$!
sleep 2
export DISPLAY=:7 QT_QPA_PLATFORM=xcb
xprop -root _KDE_NET_WM_STEREO_CONTENT_SUPPORTED > $out/root.txt 2>&1
dbus-run-session -- bash -c 'paraview --data=/fixtures/two.vtk > '$out'/paraview.log 2>&1 & p=$!; sleep 30
  xwininfo -root -tree > '$out'/tree.txt 2>&1
  python3 /rig/xshot.py '$out'/shot.png > '$out'/shot.txt 2>&1
  glxinfo -B > '$out'/glxinfo.txt 2>&1
  kill $p; sleep 2; kill -9 $p 2>/dev/null; true'
kill $xp
grep -c '"ParaView": ("paraview"' $out/tree.txt > $out/paraview-windows.txt
