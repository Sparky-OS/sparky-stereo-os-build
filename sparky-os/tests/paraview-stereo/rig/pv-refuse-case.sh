#!/bin/bash
# Inside a session: ParaView started with each of its six former output types on the command line, in the language of
# $LANG; each run's whole output and exit status in $OUT/refuse-TYPE.txt.
for t in SplitViewportHorizontal Red-Blue Interlaced Anaglyph Checkerboard Dresden "Crystal Eyes"; do
  f=$OUT/refuse-$(echo "$t" | tr ' ' _).txt
  timeout 40 paraview --stereo "--stereo-type=$t" --data=/fixtures/two.vtk > "$f.raw" 2>&1 & p=$!
  sleep 12
  if kill -0 $p 2>/dev/null; then echo "still running after 12 s (started)" >> "$f.raw"; kill $p; fi
  wait $p; echo "rc=$?" >> "$f.raw"
  grep -v '^\[' "$f.raw" > "$f"; rm -f "$f.raw"
done
