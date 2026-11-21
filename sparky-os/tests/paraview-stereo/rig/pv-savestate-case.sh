#!/bin/bash
# Inside a session, on the xcb route: Debian's ParaView with --stereo --stereo-type=Anaglyph and the two-square fixture,
# its state saved by its own File > Save State (Alt+F, S: the item has no shortcut, Ctrl+S is Save Data; the path typed into ParaView's file dialog) to $OUT/anaglyph.pvsm.
mkdir -p $HOME/.config/ParaView
printf '%s\n' '{ "settings": { "GeneralSettings": { "AutoApply": 1 } } }' > $HOME/.config/ParaView/ParaView-UserSettings.json
printf '[General]\nGeneralSettings.ShowWelcomeDialog=0\n' > $HOME/.config/ParaView/ParaView.ini
paraview --stereo --stereo-type=Anaglyph --data=/fixtures/two.vtk > $OUT/paraview.log 2>&1 &
sleep 25
wid=$(xdotool search --name '^ParaView ' 2>/dev/null | head -1); echo "window $wid" > $OUT/keys.log
xdotool windowactivate --sync "$wid" key --clearmodifiers alt+f 2>> $OUT/keys.log; sleep 1; xdotool key s 2>> $OUT/keys.log; sleep 3
python3 /rig/capture.py $OUT/shot-dialog.png > /dev/null 2>&1
xdotool type --delay 60 "$OUT/anaglyph.pvsm" 2>> $OUT/keys.log; sleep 1; xdotool key Return 2>> $OUT/keys.log; sleep 4
ls -la $OUT/anaglyph.pvsm >> $OUT/keys.log 2>&1
pid=$(ps -eo pid,comm | awk '$2=="paraview"{print $1; exit}'); [ -n "$pid" ] && kill $pid; sleep 2
