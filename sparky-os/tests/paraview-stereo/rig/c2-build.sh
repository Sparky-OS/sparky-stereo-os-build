#!/bin/bash
# Continuation 2 (row 50f): the three successors with kcmshell6 and KScreen's page as Depends, built one after another at four
# threads: paraview +stereo3d2, jmol +stereo3d3, stereo-matplotlib 0.1.2. Each is staged as a source closure, compared with
# the package it replaces (and paraview with Debian's too), and its build tree removed.
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
CA="-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro"
G=/mnt/games/k3d-temp/build/science-paraview-50f
mkdir -p work/cmp2
# a restage replaces the folders of these three versions (literal paths)
rm -rf /var/lib/sparky-lanes/science-paraview-50f/stage/paraview-6.1.1+dfsg1-3+stereo3d2 /var/lib/sparky-lanes/science-paraview-50f/stage/jmol-16.3.55+dfsg-1+stereo3d3 /var/lib/sparky-lanes/science-paraview-50f/stage/stereo-matplotlib-0.1.2
step() { # NAME VERSION_FILE_STEM STAGE_FOLDER CHANGES
  local n=$1 stem=$2 st=$3 ch=$4 W=$G/$1/pkg
  grep -q 'container exit 0' build/out-$n/exit.txt || { echo "$n: build failed"; return 1; }
  grep -q '"recipeDirty": false' $W/${stem}_amd64.sparky-build.json || { echo "$n: dirty record"; return 1; }
  python3 -I rig/stage.py $W stage/$st $W/$ch build/out-$n/recipe.log && echo "$n: staged stage/$st"
}
CPUS=4 EXTRA_MOUNTS="$CA" PRE="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get build-dep -y -q paraview=6.1.1+dfsg1-3 > /out/pre.log 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends gettext >> /out/pre.log 2>&1" \
  rig/run-recipe.sh paraview > work/run-paraview5.log 2>&1; echo "paraview runner exit $?" >> work/run-paraview5.log
if step paraview paraview_6.1.1+dfsg1-3+stereo3d2+lc1 paraview-6.1.1+dfsg1-3+stereo3d2 paraview_6.1.1+dfsg1-3+stereo3d2+lc1_amd64.changes; then
  python3 -I rig/compare-debs.py debian-debs stage/paraview-6.1.1+dfsg1-3+stereo3d2 work/cmp2 work/cmp2/paraview-stereo3d2-vs-debian.txt
  python3 -I rig/compare-debs.py stage/paraview-6.1.1+dfsg1-3+stereo3d1 stage/paraview-6.1.1+dfsg1-3+stereo3d2 work/cmp2 work/cmp2/paraview-stereo3d2-vs-stereo3d1.txt
fi
rm -rf /mnt/games/k3d-temp/build/science-paraview-50f/paraview
CPUS=4 EXTRA_MOUNTS="$CA" PRE="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get build-dep -y -q jmol=16.3.55+dfsg-1 > /out/pre.log 2>&1" \
  rig/run-recipe.sh jmol > work/run-jmol4.log 2>&1; echo "jmol runner exit $?" >> work/run-jmol4.log
if step jmol jmol_16.3.55+dfsg-1+stereo3d3+lc1 jmol-16.3.55+dfsg-1+stereo3d3 jmol_16.3.55+dfsg-1+stereo3d3+lc1_all.changes; then
  python3 -I rig/compare-debs.py stage/jmol-16.3.55+dfsg-1+stereo3d2 stage/jmol-16.3.55+dfsg-1+stereo3d3 work/cmp2 work/cmp2/jmol-stereo3d3-vs-stereo3d2.txt
fi
rm -rf /mnt/games/k3d-temp/build/science-paraview-50f/jmol
CPUS=4 SIBLINGS="/sd/libstereo-declare1_1.12.1-1+lc1_amd64.deb /sd/python3-stereo-declare_1.12.1-1+lc1_all.deb" EXTRA_MOUNTS="$CA" \
  PRE="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends dh-python pybuild-plugin-pyproject python3-all python3-setuptools gettext python3-matplotlib python3-numpy python3-pil /pool-s/stereo-layer/libstereo-policy1_1.22.0-1+lc1_amd64.deb /pool-s/stereo-declare/libstereo-declare1_1.10.0-1+lc1_amd64.deb > /out/pre.log 2>&1" \
  rig/run-recipe.sh stereo-matplotlib > work/run-mpl3.log 2>&1; echo "stereo-matplotlib runner exit $?" >> work/run-mpl3.log
if step stereo-matplotlib stereo-matplotlib_0.1.2+lc1 stereo-matplotlib-0.1.2 stereo-matplotlib_0.1.2+lc1_amd64.changes; then
  python3 -I rig/compare-debs.py stage/stereo-matplotlib-0.1.1 stage/stereo-matplotlib-0.1.2 work/cmp2 work/cmp2/stereo-matplotlib-0.1.2-vs-0.1.1.txt
fi
rm -rf /mnt/games/k3d-temp/build/science-paraview-50f/stereo-matplotlib
echo "c2-build done"
