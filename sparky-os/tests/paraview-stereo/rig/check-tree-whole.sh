#!/bin/bash
# check-tree-whole.sh NAME [SNAP|live]  -- does the published tree r1118a install whole on this Debian? In a throwaway container
# of the base image (debian:testing 2026-11-04) with rig/prelude.sh's sources (SNAP: a snapshot.debian.org instant; live:
# Debian testing of the day from deb.debian.org), Debian's components main, contrib, non-free and non-free-firmware (the NVIDIA
# packages need them), the system first brought to that Debian with a real dist-upgrade; then each amd64 and all package of
# r1118a (not -dbgsym, not -lc-hr) is simulated alone with `apt-get -s install --no-install-recommends`. For each refusal apt's
# root cause is kept: the package it finds no choice for, or the first lines of the conflict. Out: runs/tree-whole-NAME.txt,
# a summary line first, then one line per refused package.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f
NAME=${1:?name} SNAP=${2:-20261119T023717Z}
$S/scripts/drun.sh tree-$NAME sci50f-base:testing-20261104 --cpus 1 -e SNAP=$SNAP -v $S/rig:/rig:ro -v $S/keys:/run/keys:ro \
  -v $S/frozen/dmo:/dmo:ro -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro -v $S/runs:/runs --user 0:0 -- bash -c '
  set -e
  if [ "$SNAP" = live ]; then
    SNAP=20261119T023717Z; . /rig/prelude.sh >/dev/null
    sed -i -e "s|https://snapshot.debian.org/archive/debian-security/[0-9]*T[0-9]*Z|https://deb.debian.org/debian-security|" \
      -e "s|https://snapshot.debian.org/archive/debian/[0-9]*T[0-9]*Z|https://deb.debian.org/debian|" /etc/apt/sources.list.d/debian.sources
    grep -q "^URIs: https://deb.debian.org/debian\$" /etc/apt/sources.list.d/debian.sources || { echo "live sources not set" >&2; exit 1; }
    SNAP=live
  else
    . /rig/prelude.sh >/dev/null
  fi
  sed -i "s/^Components: main\$/Components: main contrib non-free non-free-firmware/" /etc/apt/sources.list.d/debian.sources
  apt-get update -qq 2>&1 | tail -3
  apt-get -y -q dist-upgrade > /tmp/du.log 2>&1 || { tail -20 /tmp/du.log; exit 1; }
  idx=$(grep -h -m1 "^Date" /var/lib/apt/lists/*_dists_testing_InRelease | cut -d" " -f2-)
  awk "/^Package:/{p=\$2} /^\$/{print p}" /repo/dists/mashtabba/main/binary-amd64/Packages /repo/dists/mashtabba/main/binary-all/Packages \
    | grep -v -E -- "-dbgsym\$|-lc-hr\$" | sort -u > /tmp/names
  : > /tmp/bad; n=0
  while read -r p; do n=$((n+1))
    if ! apt-get -s install --no-install-recommends "$p" > /tmp/o 2>&1; then
      miss=$(grep -B2 "but none of the choices are installable" /tmp/o | grep -o "Depends [^ ]*" | tail -1 | cut -d" " -f2)
      if [ -n "$miss" ]; then echo "$p | no choice for $miss" >> /tmp/bad
      else echo "$p | $(grep -A3 "Reached two conflicting" /tmp/o | tail -3 | tr -s " " | tr "\n" ";" | cut -c1-220)" >> /tmp/bad; fi
    fi
  done < /tmp/names
  bad=$(wc -l < /tmp/bad)
  { echo "SNAP=$SNAP testing-index=\"$idx\" packages=$n refused=$bad"; cat /tmp/bad; } > /runs/tree-whole-'"$NAME"'.txt
  chown 1000:1000 /runs/tree-whole-'"$NAME"'.txt; head -1 /runs/tree-whole-'"$NAME"'.txt'
