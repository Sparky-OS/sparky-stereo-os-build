#!/bin/bash
# Inside a session: ParaView as installed under gdb, with the user settings PV_SETTINGS (default Enable 3D off) and the
# two-square fixture; the backtrace of every thread when it stops goes to $OUT/gdb.txt.
mkdir -p $HOME/.config/ParaView
off='{ "settings": { "GeneralSettings": { "AutoApply": 1 }, "RenderViewSettings": { "Enable3D": 0 } } }'
printf '%s\n' "${PV_SETTINGS:-$off}" > $HOME/.config/ParaView/ParaView-UserSettings.json
printf '[General]\nGeneralSettings.ShowWelcomeDialog=0\n' > $HOME/.config/ParaView/ParaView.ini
cp $HOME/.config/ParaView/ParaView-UserSettings.json $OUT/settings.json
timeout 120 gdb -batch -ex 'set disable-randomization off' -ex run -ex 'bt 30' -ex 'thread apply all bt 8' \
  --args paraview --data=/fixtures/two.vtk > $OUT/gdb.txt 2>&1
echo "gdb rc=$?" >> $OUT/gdb.txt
