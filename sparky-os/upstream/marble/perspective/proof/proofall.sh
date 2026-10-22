#!/bin/bash
# the perspective and orthographic proofs from the probe: usage proofall.sh <tag> (IMG selects the image/flavour; here the installed build)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/marble-lane/work; export IMG=${IMG:-marble-build:2}
T=${1:-r}; O=out/$T; mkdir -p $O
run() { n=$1; shift; ./probe-run.sh $T-$n "$@" $EXTRA >/dev/null 2>&1; }
an() { n=$1; az=$2; python3 test/$az out/$T-$n/c1.png out/$T-$n/probe.json out/$T-$n/analysis.txt >/dev/null 2>&1; echo "== $n"; sed -n 2,6p out/$T-$n/analysis.txt; grep -E "^stars|outside|float item|whole" out/$T-$n/analysis.txt; echo "set_content: $(grep -c 'set_content(' out/$T-$n/client0.log)"; }
for cfg in "p2-r300 2 300" "p4-r300 4 300" "p2-r200 2 200" "p4-r200 4 200"; do set -- $cfg
  run $1 PROBE_PROJECTION=persp PROBE_STEREO=1 PROBE_SEP=$2 PROBE_RADIUS=$3 PROBE_PLAIN=1 PROBE_NOITEMS=1; an $1 analyze_persp.py
  run $1-full PROBE_PROJECTION=persp PROBE_STEREO=1 PROBE_SEP=$2 PROBE_RADIUS=$3; an $1-full analyze_persp.py
  run $1-2d PROBE_PROJECTION=persp PROBE_STEREO=1 PROBE_SEP=$2 PROBE_RADIUS=$3 PROBE_NOBACKGROUND=1 PROBE_OVERVIEW=1; an $1-2d analyze_persp.py
done
for cfg in "o2-r300 2 300" "o4-r250 4 250"; do set -- $cfg
  run $1 PROBE_STEREO=1 PROBE_SEP=$2 PROBE_RADIUS=$3; an $1 analyze.py
  run $1-2d PROBE_STEREO=1 PROBE_SEP=$2 PROBE_RADIUS=$3 PROBE_NOBACKGROUND=1 PROBE_OVERVIEW=1; an $1-2d analyze.py
done
