#!/bin/bash
# Inside a session: KScreen's page started directly (kcmshell6 kcm_kscreen) with the environment the case gives, a capture
# after 8 s (KS_XCB=1: QT_QPA_PLATFORM=xcb for kcmshell6 alone), KWin's window list and the page's own log.
if [ "${KS_XCB:-}" = 1 ]; then QT_QPA_PLATFORM=xcb kcmshell6 kcm_kscreen > $OUT/kcmshell.log 2>&1 & pid=$!
else kcmshell6 kcm_kscreen > $OUT/kcmshell.log 2>&1 & pid=$!
fi
sleep 8
python3 /rig/capture.py $OUT/shot-act.png > $OUT/shot-act.json 2>&1
python3 /rig/kwin_script.py $OUT/kwin.log '
for (const w of workspace.stackingOrder) {
  print("WIN|" + w.caption + "|" + w.frameGeometry.x + "," + w.frameGeometry.y + "," + w.frameGeometry.width + "," + w.frameGeometry.height + "|" + w.resourceClass + "|" + (w.minimized ? "min" : "shown"));
}'
sleep 1; grep -o 'WIN|.*' $OUT/kwin.log > $OUT/windows-act.txt
kill $pid 2>/dev/null
