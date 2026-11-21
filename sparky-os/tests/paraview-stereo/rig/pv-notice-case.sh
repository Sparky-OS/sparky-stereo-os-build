#!/bin/bash
# Inside a session: ParaView as installed with the user settings PV_SETTINGS and the two-square fixture (or PV_ARGS), and
# KWin's window list (caption, class, geometry, minimized, modal, transient) every 3 s for 33 s into $OUT/timeline.txt,
# then a capture; for the told-once notices.
mkdir -p $HOME/.config/ParaView
printf '%s\n' "$PV_SETTINGS" > $HOME/.config/ParaView/ParaView-UserSettings.json
printf '[General]\nGeneralSettings.ShowWelcomeDialog=0\n' > $HOME/.config/ParaView/ParaView.ini
read -r -a pvargs <<< "${PV_ARGS:---data=/fixtures/two.vtk}"
paraview "${pvargs[@]}" > $OUT/paraview.log 2>&1 &
for t in 3 6 9 12 15 18 21 24 27 30 33; do
  sleep 3
  python3 /rig/kwin_script.py $OUT/kwin.log '
print("T='$t'");
for (const w of workspace.stackingOrder) {
  print("WIN|" + w.caption + "|" + w.resourceClass + "|" + w.frameGeometry.x + "," + w.frameGeometry.y + "," + w.frameGeometry.width + "," + w.frameGeometry.height + "|min=" + w.minimized + "|modal=" + w.modal + "|transient=" + w.transient);
}'
done
python3 /rig/capture.py $OUT/shot1.png > $OUT/shot1.json 2>&1
grep -oE 'T=[0-9]+|WIN\|.*' $OUT/kwin.log > $OUT/timeline.txt
pid=$(ps -eo pid,comm | awk '$2=="paraview"{print $1; exit}'); [ -n "$pid" ] && kill $pid; sleep 2
