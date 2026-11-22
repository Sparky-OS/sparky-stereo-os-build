#!/bin/bash
# Inside a session: pv_shot.py under pvpython with user settings that name Anaglyph (7) as the screenshot's stereo mode.
mkdir -p $HOME/.config/ParaView
printf '%s\n' '{ "misc": { "SaveScreenshot": { "StereoMode": 7 } } }' > $HOME/.config/ParaView/ParaView-UserSettings.json
pvpython /rig/pv_shot.py $OUT > $OUT/pvpython.log 2>&1; echo "rc=$?" > $OUT/rc.txt
ls -la $OUT/*.png > $OUT/pngs.txt 2>&1
