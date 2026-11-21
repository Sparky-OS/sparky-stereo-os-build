#!/bin/bash
# Inside a session: the Matplotlib case (mpl_case.py) with stereo_matplotlib, captures of both eyes, the declarations,
# the declared windows' places, and with LIVE=SUNK,POPPED a change of the person's limits in the running session.
export STEREO_MATPLOTLIB_TRACE=1 MPLCONFIGDIR=$OUT/mplconfig
python3 /rig/mpl_case.py $OUT > $OUT/mpl.log 2>&1 & pid=$!
sleep ${WAIT:-14}
python3 /rig/x11_props.py > $OUT/props.json 2>&1
python3 /rig/capture.py $OUT/shot1.png > $OUT/shot1.json 2>&1
if [ -n "${LIVE:-}" ]; then
  printf '[StereoDepth]\nSunkLimit=%s\nPoppedLimit=%s\n[Xwayland]\nXwaylandEisNoPrompt=true\n' ${LIVE%,*} ${LIVE#*,} > $XDG_CONFIG_HOME/kwinrc
  python3 -c 'import gi; gi.require_version("Gio","2.0"); from gi.repository import Gio; Gio.bus_get_sync(Gio.BusType.SESSION,None).call_sync("org.kde.KWin","/KWin","org.kde.KWin","reconfigure",None,None,Gio.DBusCallFlags.NONE,5000,None)'
  sleep 4
  python3 /rig/capture.py $OUT/shot-live.png > $OUT/shot-live.json 2>&1
fi
sleep 2
python3 /rig/capture.py $OUT/shot2.png > $OUT/shot2.json 2>&1
wait $pid
echo "case python rc=$?" >> $OUT/mpl.log
