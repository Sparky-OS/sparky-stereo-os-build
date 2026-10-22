#!/bin/bash
# (g): Globe -> Perspective -> Globe in stereo within one window
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/marble-lane/work; export IMG=${IMG:-marble-build:2}; n=${1:-sw}
envj='{"PROBE_STEREO":"1","PROBE_SEP":"2","PROBE_RADIUS":"300","PROBE_PLAIN":"1","PROBE_NOITEMS":"1","PROBE_DUMP":"/w/out/'$n'/probe.json","PROBE_DELAY_MS":"5000",'"$EXTRAJ"'"PROBE_SWITCHES":"8000:persp,16000:globe"}'
mkdir -p out/$n
./rig.sh $n "[{\"argv\":[\"/w/run-probe.sh\"],\"env\":$envj}]" '[["wait",7],["cap","a"],["wait",6],["cap","b"],["wait",8],["cap","c"]]'
O=out/$n
echo "declarations: create=$(grep -c 'content_manager_v1#.*create' $O/client0.log) set_content=$(grep -c 'set_content(' $O/client0.log)"
python3 test/analyze.py $O/a.png $O/probe.json $O/a.txt >/dev/null; python3 test/analyze_persp.py $O/b.png $O/probe.json.1 $O/b.txt >/dev/null; python3 test/analyze.py $O/c.png $O/probe.json.2 $O/c.txt >/dev/null
for x in a b c; do echo "== $x"; sed -n 1,3p $O/$x.txt | cut -c1-250; grep -E "^stars|outside" $O/$x.txt; done
cat $O/probe.json.1 | grep -E "projection|radius"
