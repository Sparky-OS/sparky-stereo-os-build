#!/bin/bash
# Inside a session: notice_probe.py $MODE, then KWin's window list at 7 s.
python3 /rig/notice_probe.py ${MODE:?} > $OUT/probe.log 2>&1 &
sleep 7
python3 /rig/kwin_script.py $OUT/kwin.log 'for (const w of workspace.stackingOrder) { print("WIN|" + w.caption + "|modal=" + w.modal); }'
sleep 1; grep -o 'WIN|.*' $OUT/kwin.log > $OUT/windows.txt
wait
