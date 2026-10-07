#!/bin/bash
# usage: app-run.sh <name> <stock|patched> <marble|marble-qt> [ENV=VAL ...]; steps in $STEPS (json) default: wait 25, cap
name=$1; flavor=$2; app=$3; shift 3
envj=$(python3 -c "
import json,sys
e={'FLAVOR':'$flavor','APP':'$app'}
for a in sys.argv[1:]:
    k,v=a.split('=',1); e[k]=v
print(json.dumps(e))" "$@")
case $flavor in stock) export IMG=marble-stock:2;; pkg) export IMG=marble-pkg:1;; *) export IMG=marble-build:2;; esac
SCREEN=${SCREEN:-1280x800} ./rig.sh $name "[{\"argv\":[\"/w/run-app.sh\"],\"env\":$envj}]" "${STEPS:-[[\"wait\",30],[\"cap\",\"c1\"],[\"wait\",2],[\"cap\",\"c2\"]]}"
cat out/$name/c1.capture.txt; head -5 out/$name/client0.log
