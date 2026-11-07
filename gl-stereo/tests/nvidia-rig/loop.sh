#!/bin/sh
# usage: loop.sh N PLATFORM PATHMODE PROG [secs]
N=$1; shift
i=0
while [ $i -lt $N ]; do
  i=$((i+1))
  out=$(sh /rig/session.sh "$@" 2>&1 | grep -E '^(CHECK|RESULT)' | tr '\n' ' ')
  v=$(echo "$out" | sed -n 's/.*"verdict": "\([A-Z-]*\)".*/\1/p')
  echo "run $i ${v:-NOCHECK} :: $(echo $out | cut -c1-60)"
done
