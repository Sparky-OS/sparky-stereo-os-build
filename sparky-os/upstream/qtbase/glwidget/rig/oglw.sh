#!/bin/bash
# usage: oglw.sh <name> <sw|gpu>   tst_qopenglwidget from the dev build on native Wayland under headless KWin
n=$1; mode=$2
extra=(); [ "$mode" = sw ] && extra=(SOFT=1)
env IMG=qtgl-run:dbg NAME=$n WAIT=${W:-170} MYQT=1 PRE="$NODECO" "${extra[@]}" CMD="sh -c 'cd /qtbuild/tests/auto/widgets/widgets/qopenglwidget && ./tst_qopenglwidget $TESTARGS'" ./drun.sh >/dev/null 2>&1
echo "== $n"; grep -E "^Totals|FAIL!|Received signal" ../ev/$n/app.raw | head -8
