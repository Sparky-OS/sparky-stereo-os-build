#!/bin/bash
# Inside a session: ParaView as installed under gdb with the user settings PV_SETTINGS, the two-square fixture, for WAIT
# seconds; gdb prints each call of the functions in TRACE (space-separated) with three frames of its caller, to $OUT/gdb.txt.
mkdir -p $HOME/.config/ParaView
printf '%s\n' "$PV_SETTINGS" > $HOME/.config/ParaView/ParaView-UserSettings.json
printf '[General]\nGeneralSettings.ShowWelcomeDialog=0\n' > $HOME/.config/ParaView/ParaView.ini
cmds=$OUT/gdb.cmds; : > $cmds
echo 'set disable-randomization off' >> $cmds; echo 'set breakpoint pending on' >> $cmds
for f in $TRACE; do printf 'break %s\ncommands\nsilent\nprintf "HIT %s\\n"\nshell date +%%T.%%N\nbt %s\ncontinue\nend\n' "$f" "$f" "${BT:-3}" >> $cmds; done
echo 'shell date +%T.%N' >> $cmds
echo 'run' >> $cmds
timeout ${WAIT:-40} gdb -batch -x $cmds --args paraview --data=/fixtures/two.vtk > $OUT/gdb.txt 2>&1
echo "gdb rc=$?" >> $OUT/gdb.txt
