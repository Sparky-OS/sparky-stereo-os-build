#!/bin/bash
# Inside a session, on the xcb route (keys through xdotool): ParaView as installed with the two-square fixture, then
#   Edit > Settings... (Alt+E, Up three times: the menu ends Settings..., Reset to Default Settings, Set Main Window Title)
#   captured as opened (shot-settings-0), on its Render View tab (shot-settings-1), with "stereo" typed in the dialog's
#   search box (shot-settings-2); before that, the main window (shot-main); after it, the Properties panel with its
#   advanced properties shown and "stereo" in its search box (shot-props).
mkdir -p $HOME/.config/ParaView
printf '%s\n' '{ "settings": { "GeneralSettings": { "AutoApply": 1 } } }' > $HOME/.config/ParaView/ParaView-UserSettings.json
printf '[General]\nGeneralSettings.ShowWelcomeDialog=0\n' > $HOME/.config/ParaView/ParaView.ini
read -r -a pvargs <<< "${PV_ARGS:-}"   # e.g. --stereo --stereo-type=Anaglyph, split on spaces
paraview "${pvargs[@]}" --data=/fixtures/two.vtk > $OUT/paraview.log 2>&1 &
sleep ${WAIT:-25}
python3 /rig/kwin_script.py $OUT/kwin.log '
for (const w of workspace.stackingOrder) {
  if (w.caption.indexOf("Output Messages") >= 0) { w.minimized = true; }
  else if (w.normalWindow && w.caption.indexOf("ParaView ") == 0) { w.setMaximize(true, true); }
}'
sleep 4
python3 /rig/capture.py $OUT/shot-main.png > $OUT/shot-main.json 2>&1
wid=$(xdotool search --name '^ParaView ' 2>/dev/null | head -1); echo "window $wid" > $OUT/keys.log
xdotool windowactivate --sync "$wid" key --clearmodifiers alt+e 2>> $OUT/keys.log; sleep 1
xdotool key Up Up Up Return 2>> $OUT/keys.log; sleep 3
python3 /rig/capture.py $OUT/shot-settings-0.png > /dev/null 2>&1
# clicks at the places the 1920x1080 output gives (ParaView's labels are English in every language in Debian's build):
# the dialog from the keyboard only (clicks inside it did not land where the capture shows them): focus starts in its search
# box; Shift+Tab to the tab bar, Right four times (the first is lost) to Render View, Tab twice (past the scroll arrow) to the search box, Escape twice to clear and close; the Properties panel's advanced gear and search box
xdotool key shift+Tab 2>> $OUT/keys.log; sleep 1; xdotool key --delay 500 Right Right Right Right 2>> $OUT/keys.log; sleep 2
python3 /rig/capture.py $OUT/shot-settings-1a.png > /dev/null 2>&1
if [ "${TAB_KEYS:-}" = 1 ]; then xdotool mousemove 940 230 click 1; sleep 0.5; xdotool key ctrl+Next ctrl+Next ctrl+Next 2>> $OUT/keys.log; sleep 2; fi
python3 /rig/capture.py $OUT/shot-settings-1.png > /dev/null 2>&1
xdotool key --delay 500 Tab Tab 2>> $OUT/keys.log; sleep 1
python3 /rig/capture.py $OUT/shot-settings-1b.png > /dev/null 2>&1
xdotool type --delay 80 stereo 2>> $OUT/keys.log; sleep 2
python3 /rig/capture.py $OUT/shot-settings-2.png > /dev/null 2>&1
xwininfo -root -tree > $OUT/tree.txt 2>&1
xdotool key --delay 500 Escape Escape 2>> $OUT/keys.log; sleep 2
xdotool mousemove 322 594 click 1 2>> $OUT/keys.log; sleep 1
xdotool mousemove 160 594 click 1 2>> $OUT/keys.log; sleep 1; xdotool type --delay 80 stereo 2>> $OUT/keys.log; sleep 2
python3 /rig/capture.py $OUT/shot-props.png > /dev/null 2>&1
# OPEN_COMBO=1 (Debian's ParaView with --stereo): open the Stereo Type list the search left at the panel's (130,750)
if [ "${OPEN_COMBO:-}" = 1 ]; then xdotool mousemove 130 750 click 1 2>> $OUT/keys.log; sleep 2; python3 /rig/capture.py $OUT/shot-props-list.png > /dev/null 2>&1; xdotool key Escape; fi
pid=$(ps -eo pid,comm | awk '$2=="paraview"{print $1; exit}'); [ -n "$pid" ] && kill $pid; sleep 2
