#!/bin/bash
# tree-refusal-causes.sh NAME SNAP  -- for each package check-tree-whole.sh refused (runs/tree-whole-NAME.txt), apt's root cause
# on the same sources: the "Reached two conflicting assignments" block, reduced to the package apt finds no choice for (or
# the conflict); then, for each such package, whether Debian's index at SNAP, r1118a or the frozen deb-multimedia has it at
# all. Out: runs/tree-causes-NAME.txt (one line per refused package: name, the missing or conflicting package, where it is).
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f
NAME=${1:?name} SNAP=${2:?snapshot instant}
grep '^== ' $S/runs/tree-whole-$NAME.txt | cut -c4- > $S/work/refused-$NAME.txt
$S/scripts/drun.sh causes-$NAME sci50f-base:testing-20261104 --cpus 1 -e SNAP=$SNAP -v $S/rig:/rig:ro -v $S/keys:/run/keys:ro \
  -v $S/frozen/dmo:/dmo:ro -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro -v $S/work:/w -v $S/runs:/runs --user 0:0 -- bash -c '
  . /rig/prelude.sh >/dev/null
  while read -r p; do
    blk=$(apt-get -s install --no-install-recommends "$p" 2>&1 | grep -A8 "Reached two conflicting" || true)
    miss=$(printf "%s\n" "$blk" | grep -B2 "but none of the choices are installable" | grep -o "Depends [^ ]*" | tail -1 | cut -d" " -f2)
    if [ -n "$miss" ]; then
      where=$(apt-cache policy "$miss" 2>/dev/null | grep -c "^     " || true)
      echo "$p | no choice for $miss | versions known to apt: $where"
    else
      echo "$p | $(printf "%s\n" "$blk" | sed -n 2,4p | tr -s " " | tr "\n" ";" | cut -c1-200)"
    fi
  done < /w/refused-'"$NAME"'.txt > /runs/tree-causes-'"$NAME"'.txt
  chown 1000:1000 /runs/tree-causes-'"$NAME"'.txt; wc -l < /runs/tree-causes-'"$NAME"'.txt'
