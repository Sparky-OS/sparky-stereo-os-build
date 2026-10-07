#!/bin/bash
# usage: probe-run.sh <name> [ENV=VAL ...]   one probe run with a capture of the screen
name=$1; shift
envj=$(python3 -c "
import json,sys
e={'PROBE_DUMP':'/w/out/$name/probe.json','PROBE_DELAY_MS':'6000'}
for a in sys.argv[1:]:
    k,v=a.split('=',1); e[k]=v
print(json.dumps(e))" "$@")
SCREEN=${SCREEN:-1280x800} ./rig.sh $name "[{\"argv\":[\"/w/run-probe.sh\"],\"env\":$envj}]" '[["wait",9],["cap","c1"],["wait",1],["cap","c2"]]'
ls out/$name; cat out/$name/c1.capture.txt
