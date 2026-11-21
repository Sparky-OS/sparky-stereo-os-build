#!/bin/bash
# Inside a session (xcb): Enable 3D switched off from the View menu, the notice closed, ParaView quit with Ctrl+Q; then
# ParaView started again with the settings it saved. first/ and second/ hold each start's files (pv-case.sh's).
mkdir -p $OUT/first $OUT/second
ln -sf $OUT/kwin.log $OUT/first/kwin.log; ln -sf $OUT/kwin.log $OUT/second/kwin.log
OUT=$OUT/first MENU=1 MENU_KEYS="Up Up Return" QUIT=1 bash /rig/pv-case.sh
OUT=$OUT/second PV_KEEP_SETTINGS=1 bash /rig/pv-case.sh
