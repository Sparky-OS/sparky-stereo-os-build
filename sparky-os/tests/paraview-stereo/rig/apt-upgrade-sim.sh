#!/bin/bash
# The brief's item 4: apt's simulated upgrade from Debian's packages on the published tree. In a container of sci50f-rig:1
# (the published tree r1118a at pin 1001, Debian's paraview and vtk9): every architecture-dependent binary package of Debian's
# vtk9 9.6.2+ds-3 and paraview 6.1.1+dfsg1-3 installed from Debian, then the stage added as a flat repository (Origin
# "Sparky Stereo OS", as in a round) and `apt-get -s full-upgrade`; its Inst, Remv and Conf lines go to runs/apt-upgrade-sim.txt.
#   STAGE="DIR..."  the stage folders (default: the vtk9 and paraview ones)
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
STAGE=${STAGE:-"$S/stage/vtk9-9.6.2+ds-3+stereo3d1 $S/stage/paraview-6.1.1+dfsg1-3+stereo3d1"}
F=$S/flat/upgrade-sim; rm -rf /var/lib/sparky-lanes/science-paraview-50f/flat/upgrade-sim; mkdir -p "$F"
for st in $STAGE; do cp "$st"/*.deb "$F/"; done; rm -f "$F"/*-dbgsym_*.deb
python3 -I $S/rig/flat-index.py "$F"
$S/scripts/drun.sh upgrade-sim sci50f-rig:1 --cpus 1 -v "$F":/flat:ro -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro \
  -v $S/keys:/run/keys:ro -v $S/runs:/runs --user 0:0 -- sh -c "set -e
  sh /run/https-only-apt.sh >/dev/null; export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq 2>&1 | tail -3
  pkgs='libvtk9.6=9.6.2+ds-3 libvtk9.6-qt=9.6.2+ds-3 libvtk9-dev=9.6.2+ds-3 libvtk9-qt-dev=9.6.2+ds-3 python3-vtk9=9.6.2+ds-3 libvtk9-java=9.6.2+ds-3 vtk9=9.6.2+ds-3 paraview=6.1.1+dfsg1-3 paraview-dev=6.1.1+dfsg1-3 python3-paraview=6.1.1+dfsg1-3'
  apt-get install -y -q --no-install-recommends \$pkgs > /tmp/debian.log 2>&1 || { tail -20 /tmp/debian.log; exit 1; }
  # the rest of the system brought up to date first (the rig's base is older than today's testing), so the simulation shows
  # only what the stage changes
  apt-get -y -q full-upgrade > /tmp/base-upgrade.log 2>&1 || { tail -20 /tmp/base-upgrade.log; exit 1; }
  apt-mark hold libvtk9.6 libvtk9.6-qt libvtk9-dev libvtk9-qt-dev python3-vtk9 libvtk9-java vtk9 paraview paraview-dev python3-paraview > /dev/null
  dpkg-query -W libvtk9.6 libvtk9.6-qt libvtk9-dev libvtk9-qt-dev python3-vtk9 libvtk9-java vtk9 paraview paraview-dev python3-paraview > /runs/apt-upgrade-before.txt
  apt-mark unhold libvtk9.6 libvtk9.6-qt libvtk9-dev libvtk9-qt-dev python3-vtk9 libvtk9-java vtk9 paraview paraview-dev python3-paraview > /dev/null
  echo 'deb [trusted=yes] file:/flat ./' > /etc/apt/sources.list.d/stage.list
  apt-get update -qq 2>&1 | tail -3
  apt-get -s full-upgrade > /tmp/sim.txt 2>&1
  grep -E '^(Inst|Remv|Conf|Purg)|upgraded|newly installed' /tmp/sim.txt > /runs/apt-upgrade-sim.txt
  chown 1000:1000 /runs/apt-upgrade-sim.txt /runs/apt-upgrade-before.txt"
cat $S/runs/apt-upgrade-sim.txt
