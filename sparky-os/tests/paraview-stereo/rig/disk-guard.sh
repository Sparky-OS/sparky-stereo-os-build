#!/bin/bash
# disk-guard.sh CONTAINER NAME: every 60 s, progress and free space into work/disk-guard.log; pauses CONTAINER when /mnt/games
# has less than 2.5 GB free (its floor is 2 GB), and says so; / is logged only (the build writes its temporary files and the
# gate's scratch on /mnt/games, nothing large on /); ends when CONTAINER is gone.
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
S=/var/lib/sparky-lanes/science-paraview-50f; c=$1; log=$S/work/disk-guard.log
while docker inspect "$c" >/dev/null 2>&1; do
  free=$(df -B1M --output=avail /mnt/games | tail -1 | tr -d ' ')
  rootfree=$(df -B1M --output=avail / | tail -1 | tr -d ' ')
  n=$(grep -c 'Building C' $S/build/out-$2/recipe.log 2>/dev/null)
  echo "$(date -u +%H:%M:%S) objects=$n games_free_MB=$free root_free_MB=$rootfree $(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)" >> $log
  if [ "$free" -lt 2560 ] && [ "$(docker inspect -f '{{.State.Status}}' "$c")" = running ]; then
    docker pause "$c" >/dev/null && echo "$(date -u +%H:%M:%S) PAUSED $c: /mnt/games under 2.5 GB free" >> $log
  fi
  sleep 60
done
echo "$(date -u +%H:%M:%S) $c gone, guard ends" >> $log
