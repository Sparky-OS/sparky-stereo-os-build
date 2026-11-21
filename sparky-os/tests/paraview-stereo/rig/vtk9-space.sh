#!/bin/bash
# vtk9-space.sh: keeps the vtk9 build inside /mnt/games's room by removing, inside the build container, what no later step
# reads, each only after its last reader (Debian's vtk9 9.6.2+ds-3 rules, read 2026-11-21):
#   1. the object files, once "debian/rules override_dh_auto_install-arch" starts: compiling and linking are over, dh's
#      install runs with CMAKE_SKIP_INSTALL_ALL_DEPENDENCY=ON (no up-to-date check of the objects) and the other-Python loop is
#      empty in this builder (py3versions -s is python3.14 alone);
#   2. the rest of the build tree, once "dh_install -a" starts: dh_auto_install, its last reader, is over.
# The tree's size is logged before each removal (the report's object tree size). Ends when the container is gone.
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
S=/var/lib/sparky-lanes/science-paraview-50f; c=sci50f-build-vtk9; log=$S/work/vtk9-space.log; L=$S/build/out-vtk9/recipe.log
B=/work/pkg/vtk9-9.6.2+ds/debian/build-python3.14; H=/mnt/games/k3d-temp/build/science-paraview-50f/vtk9/pkg/vtk9-9.6.2+ds/debian/build-python3.14
wait_for() { until grep -qE "$1" $L; do docker inspect "$c" >/dev/null 2>&1 || { echo "$(date -u +%T) $c gone" >> $log; exit 0; }; sleep 2; done; }
free() { df -B1M --output=avail /mnt/games | tail -1 | tr -d ' '; }
wait_for '^ *debian/rules override_dh_auto_install-arch'
echo "$(date -u +%T) install started; tree $(du -sm $H | cut -f1) MB, objects $(find $H -name '*.o' | wc -l) ($(find $H -name '*.o' -printf '%s\n' | awk '{s+=$1} END{printf "%.0f", s/1048576}') MB), libraries $(du -sm $H/lib | cut -f1) MB, /mnt/games free $(free) MB" >> $log
docker exec $c find $B -name '*.o' -delete
echo "$(date -u +%T) object files removed; /mnt/games free $(free) MB" >> $log
wait_for '^   dh_install -a'
echo "$(date -u +%T) dh_install started; tree $(du -sm $H | cut -f1) MB, debian/tmp $(du -sm $H/../tmp | cut -f1) MB, /mnt/games free $(free) MB" >> $log
docker exec $c rm -rf $B
echo "$(date -u +%T) build tree removed; /mnt/games free $(free) MB" >> $log
