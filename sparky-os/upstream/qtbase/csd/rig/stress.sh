#!/bin/bash
# repeat the stereo CSD case N times, count segfaults and good captures
cd "$(dirname "$0")/.."; export EVROOT=$PWD/evidence IMG=qtbase-proof:ours-in
n=${1:-10}; soft=${2:-}
crash=0; good=0
for i in $(seq 1 $n); do
  NODECO=1 CSD=1 SOFT=$soft WAIT=6 timeout 100 bash rig/drun.sh stress bash /rig/client-qt.sh >/dev/null 2>&1
  if grep -q "Segmentation\|app_rc=139" evidence/stress/app.log evidence/stress/capture.log 2>/dev/null; then crash=$((crash+1)); fi
  out=$(python3 rig/analyze-csd.py evidence/stress/window.png 2>/dev/null)
  echo "$out" | grep -q "opaque decoration identical in both eyes: True" && echo "$out" | grep -q "same content box in both eyes: True" && good=$((good+1))
done
echo "runs=$n soft=${soft:-0} crashes=$crash good_captures=$good"
