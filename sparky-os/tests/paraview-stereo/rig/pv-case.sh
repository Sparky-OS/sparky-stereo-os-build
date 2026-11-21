#!/bin/bash
# Inside a session (session.sh): ParaView as installed, with the two-square fixture (lane 50e's paraview-case.sh, extended).
#   PV_STEREO     a stereo type: adds --stereo --stereo-type="$PV_STEREO"; "-" adds --stereo alone; empty adds nothing
#   PV_EXTRA      more arguments, split on spaces (no argument here contains one)
#   PV_NODATA=1   no --data (a state file opens its own)
#   PV_SETTINGS   the user settings file's JSON (default: Auto Apply on)
#   MENU=1        after the captures, open the View menu (xcb: Alt+V through xdotool) and capture it as shot-menu.png
#   MENU_KEYS     with MENU=1: keys sent after Alt+V instead of Escape ("Up Up Return": Enable 3D; "Up Return": 3D display
#                 settings...), then shot-act.png, windows-act.txt, act-processes.txt and settings-after.json
#   QUIT=1        with MENU_KEYS: then Return (the notice's OK) and Ctrl+Q, waiting up to 30 s for ParaView to exit by
#                 itself (settings-after-quit.json, quit.txt)
#   PV_KEEP_SETTINGS=1  keep the user settings file a previous start left (written only when there is none)
#   WAIT          seconds before the first capture (default 25)
# Writes in $OUT: paraview.log (stdout and stderr, Wayland debug lines out), wl.txt (the declaration lines), rc.txt,
# windows.txt (KWin's windows: caption, frame, class), props.json, shot1.png/json, shot2.png/json, tree.txt,
# drawbuffer-warnings.txt (count of "Error in cache state for GL_DRAW_BUFFER"), maps.txt (the VTK and ParaView
# libraries the process has loaded, from /proc/PID/maps).
mkdir -p $HOME/.config/ParaView
default_settings='{ "settings": { "GeneralSettings": { "AutoApply": 1 } } }'
if [ "${PV_KEEP_SETTINGS:-}" != 1 ] || [ ! -s $HOME/.config/ParaView/ParaView-UserSettings.json ]; then
  printf '%s\n' "${PV_SETTINGS:-$default_settings}" > $HOME/.config/ParaView/ParaView-UserSettings.json
fi
printf '[General]\nGeneralSettings.ShowWelcomeDialog=0\n' > $HOME/.config/ParaView/ParaView.ini
args=()
[ "${PV_NODATA:-}" = 1 ] || args+=(--data=/fixtures/two.vtk)
if [ "${PV_STEREO:-}" = "-" ]; then args=(--stereo "${args[@]}");
elif [ -n "${PV_STEREO:-}" ]; then args=(--stereo "--stereo-type=$PV_STEREO" "${args[@]}"); fi
read -r -a extra <<< "${PV_EXTRA:-}"
args+=("${extra[@]}")
printf '%q ' paraview "${args[@]}" > $OUT/command.txt; echo >> $OUT/command.txt
( WAYLAND_DEBUG=client paraview "${args[@]}"; echo "rc=$?" > $OUT/rc.txt ) 2>&1 \
  | tee >(grep -E --line-buffered "kde_stereo_content|set_content|get_subsurface|wl_display.*error" > $OUT/wl.txt) \
  | grep -v "^\[" > $OUT/paraview.log &
sleep ${WAIT:-25}
pid=$(ps -eo pid,comm | awk '$2=="paraview"{print $1; exit}')
[ -n "$pid" ] && grep -oE '/[^ ]*lib(vtk|pq)[^ ]*\.so[^ ]*' /proc/$pid/maps | sort -u > $OUT/maps.txt
python3 /rig/kwin_script.py $OUT/kwin.log '
for (const w of workspace.stackingOrder) {
  if (w.caption.indexOf("Output Messages") >= 0) { w.minimized = true; }
  else if (w.normalWindow && w.caption.indexOf("ParaView ") == 0) { w.setMaximize(true, true); }
}'
sleep 6
python3 /rig/kwin_script.py $OUT/kwin.log '
for (const w of workspace.stackingOrder) {
  print("WIN|" + w.caption + "|" + w.frameGeometry.x + "," + w.frameGeometry.y + "," + w.frameGeometry.width + "," + w.frameGeometry.height + "|" + w.resourceClass + "|" + (w.minimized ? "min" : "shown"));
}'
sleep 1
grep -o 'WIN|.*' $OUT/kwin.log > $OUT/windows.txt
python3 /rig/x11_props.py > $OUT/props.json 2>&1
python3 /rig/capture.py $OUT/shot1.png > $OUT/shot1.json 2>&1
sleep 3
python3 /rig/capture.py $OUT/shot2.png > $OUT/shot2.json 2>&1
xwininfo -root -tree > $OUT/tree.txt 2>&1
if [ "${MENU:-}" = 1 ]; then
  wid=$(xdotool search --name '^ParaView ' 2>/dev/null | head -1)
  [ -n "$wid" ] && xdotool windowactivate --sync "$wid" key --clearmodifiers alt+v 2>> $OUT/menu.log
  sleep 2
  python3 /rig/capture.py $OUT/shot-menu.png > $OUT/shot-menu.json 2>&1
  if [ -n "${MENU_KEYS:-}" ]; then
    xdotool key --clearmodifiers $MENU_KEYS 2>> $OUT/menu.log
    sleep 4
    python3 /rig/capture.py $OUT/shot-act.png > $OUT/shot-act.json 2>&1
    n=$(grep -c 'WIN|' $OUT/kwin.log)
    python3 /rig/kwin_script.py $OUT/kwin.log '
for (const w of workspace.stackingOrder) {
  print("WIN|" + w.caption + "|" + w.frameGeometry.x + "," + w.frameGeometry.y + "," + w.frameGeometry.width + "," + w.frameGeometry.height + "|" + w.resourceClass + "|" + (w.minimized ? "min" : "shown"));
}'
    sleep 1
    grep -o 'WIN|.*' $OUT/kwin.log | tail -n +$((n + 1)) > $OUT/windows-act.txt
    ps -eo pid,args | grep -E '[k]cmshell|[s]ystemsettings|[k]screen' > $OUT/act-processes.txt
    cp $HOME/.config/ParaView/ParaView-UserSettings.json $OUT/settings-after.json
    if [ "${QUIT:-}" = 1 ]; then
      xdotool key --clearmodifiers Return 2>> $OUT/menu.log; sleep 1
      wid=$(xdotool search --name '^ParaView ' 2>/dev/null | head -1)
      [ -n "$wid" ] && xdotool windowactivate --sync "$wid" key --clearmodifiers ctrl+q 2>> $OUT/menu.log
      for i in $(seq 30); do kill -0 $pid 2>/dev/null || break; sleep 1; done
      kill -0 $pid 2>/dev/null && echo "still running after 30 s" > $OUT/quit.txt || echo "exited by itself" > $OUT/quit.txt
      cp $HOME/.config/ParaView/ParaView-UserSettings.json $OUT/settings-after-quit.json
    fi
  else
    xdotool key Escape 2>> $OUT/menu.log
  fi
fi
[ -n "$pid" ] && kill $pid 2>/dev/null; sleep 2
[ -n "$pid" ] && kill -9 $pid 2>/dev/null
sleep 1
grep -c 'Error in cache state for GL_DRAW_BUFFER' $OUT/paraview.log > $OUT/drawbuffer-warnings.txt
