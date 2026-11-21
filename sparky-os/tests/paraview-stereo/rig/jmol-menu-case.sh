#!/bin/bash
# Inside a session: Jmol as installed (Enable 3D as the person left it), the Display menu opened from the keyboard by its
# mnemonic MENU_KEY in that language (Jmol's window activated first, the pointer at MENU_X,MENU_Y), then a capture of both eyes.
mkdir -p $HOME/.jmol
[ "${ENABLE3D:-}" = 0 ] && printf 'enable3D=false\n' > $HOME/.jmol/properties
jmol -Duser.home=$HOME -s /fixtures/jmol-case.spt > $OUT/jmol.log 2>&1 & pid=$!
sleep ${WAIT:-20}
wid=$(xdotool search --classname 'org-openscience-jmol-app-jmolpanel-JmolPanel' 2>/dev/null | while read w; do xwininfo -id $w | grep -q 'Map State: IsViewable' && xwininfo -id $w | grep -q 'Width: [3-9][0-9][0-9]' && echo $w; done | head -1)
echo "window $wid" >> $OUT/menu.log
xdotool mousemove ${MENU_X:?} ${MENU_Y:?} 2>> $OUT/menu.log; sleep 0.5
[ -n "$wid" ] && xdotool windowactivate --sync $wid 2>> $OUT/menu.log
sleep 0.5; xdotool key --clearmodifiers ${MENU_KEY:?} ${MENU_KEY2:-} 2>> $OUT/menu.log
sleep ${MENU_WAIT:-3}
python3 /rig/capture.py $OUT/shot-menu.png > $OUT/shot-menu.json 2>&1
python3 /rig/x11_props.py > $OUT/props.json 2>&1
xwininfo -root -tree > $OUT/tree-menu.txt 2>&1
if [ -n "${ACT_KEYS:-}" ]; then
xdotool key --clearmodifiers $ACT_KEYS 2>> $OUT/menu.log
sleep 8
python3 /rig/capture.py $OUT/shot-act.png > $OUT/shot-act.json 2>&1
python3 /rig/kwin_script.py $OUT/kwin.log '
for (const w of workspace.stackingOrder) {
  print("WIN|" + w.caption + "|" + w.frameGeometry.x + "," + w.frameGeometry.y + "," + w.frameGeometry.width + "," + w.frameGeometry.height + "|" + w.resourceClass + "|" + (w.minimized ? "min" : "shown"));
}'
sleep 1
grep -o 'WIN|.*' $OUT/kwin.log > $OUT/windows-act.txt
ps -eo pid,args | grep -E '[k]cmshell|[s]ystemsettings' > $OUT/act-processes.txt
else
xdotool key Escape 2>> $OUT/menu.log
fi
kill $pid 2>/dev/null; sleep 1
