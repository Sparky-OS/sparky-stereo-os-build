#!/bin/bash
# Inside a session (session.sh): one program as installed, for the rows of a shared library (vtk9) that the program loads.
#   PROG        the command;  PROG_ARGS  its arguments, split on spaces;  PROC  the process name (default: PROG)
#   WAIT        seconds before the first capture (default 25)
# Writes in $OUT: prog.log (stdout and stderr, Wayland debug lines out), wl.txt (declaration lines), rc.txt (when it ended
# by itself), maps.txt (the VTK and F3D libraries the process has loaded, from /proc/PID/maps), windows.txt (KWin's
# windows: caption, frame, class), props.json, shot1.png/json, shot2.png/json, tree.txt.
read -r -a args <<< "${PROG_ARGS:-}"
printf '%q ' "$PROG" "${args[@]}" > $OUT/command.txt; echo >> $OUT/command.txt
( WAYLAND_DEBUG=client "$PROG" "${args[@]}"; echo "rc=$?" > $OUT/rc.txt ) 2>&1 \
  | tee >(grep -E --line-buffered "kde_stereo_content|set_content|get_subsurface|wl_display.*error" > $OUT/wl.txt) \
  | grep -v "^\[" > $OUT/prog.log &
sleep ${WAIT:-25}
proc=${PROC:-$(basename "$PROG")}
pid=$(pgrep -n -f "$proc" | head -1)
[ -n "$pid" ] && grep -oE '/[^ ]*lib(vtk|f3d)[^ ]*\.so[^ ]*' /proc/$pid/maps | sort -u > $OUT/maps.txt
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
[ -n "$pid" ] && kill $pid 2>/dev/null; sleep 2
[ -n "$pid" ] && kill -9 $pid 2>/dev/null
sleep 1
