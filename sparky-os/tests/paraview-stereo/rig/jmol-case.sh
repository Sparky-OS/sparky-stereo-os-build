#!/bin/bash
# Inside a session: Jmol with the six-atom fixture (fixtures/jmol-case.spt plus EXTRA script lines) at its own size, the X11
# tree, two captures. ENABLE3D=0 writes the person's Jmol preference enable3D=false first (as unticking Enable 3D does).
mkdir -p $HOME/.jmol
[ "${ENABLE3D:-}" = 0 ] && printf 'enable3D=false\n' > $HOME/.jmol/properties
cp /fixtures/jmol-case.spt $OUT/case.spt
[ -n "${EXTRA:-}" ] && printf '%s\n' "$EXTRA" >> $OUT/case.spt
java -XshowSettings:properties -version 2>&1 | grep -E 'awt.toolkit|java.version =' > $OUT/java.txt
jmol -Duser.home=$HOME ${JMOL_ARGS:-} -s $OUT/case.spt > $OUT/jmol.log 2>&1 & pid=$!
sleep ${WAIT:-20}
python3 /rig/kwin_script.py $OUT/kwin.log '
for (const w of workspace.stackingOrder) {
  print("WIN|" + w.caption + "|" + w.frameGeometry.x + "," + w.frameGeometry.y + "," + w.frameGeometry.width + "," + w.frameGeometry.height + "|" + w.resourceClass);
}'
sleep ${WAIT2:-10}
python3 /rig/x11_props.py > $OUT/props.json 2>&1
xwininfo -root -tree > $OUT/tree.txt 2>&1
python3 /rig/capture.py $OUT/shot1.png > $OUT/shot1.json 2>&1
sleep 3
python3 /rig/capture.py $OUT/shot2.png > $OUT/shot2.json 2>&1
kill $pid 2>/dev/null; sleep 1
