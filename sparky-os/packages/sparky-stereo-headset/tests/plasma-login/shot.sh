#!/bin/bash
# shot.sh NAME: capture the screen through KWin's ScreenShot2 into /out/NAME.png (inside the rig, after session-up.sh)
. /home/rig/env.sh; python3 /skills/capture.py "/out/$1.png"
