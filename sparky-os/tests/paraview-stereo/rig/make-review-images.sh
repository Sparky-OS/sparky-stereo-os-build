#!/bin/bash
# make-review-images.sh [all | NAME...]  -- the review images of lane 50f, from the base debian:testing image (7b0e755e), Debian
# testing from snapshot.debian.org at 20261121T093758Z (rig/SNAPSHOT.md), the frozen deb-multimedia and the stage:
#   1          Debian's paraview and vtk9 on the published tree r1118a (the red rows)
#   green-vtk  Debian's paraview on the edition's vtk9 (the vtk9 folder in stage/)
#   green-pv2  the edition's paraview +stereo3d2 on the edition's vtk9
#   green-i6b  jmol +stereo3d3 and python3-stereo-matplotlib 0.1.2
#   pv2-ref    paraview +stereo3d2 on the vtk9 kept in ref/ (made only when ref/ holds a vtk9 folder: the red row of a new vtk9)
# With no argument only the missing images are made; "all" or names remake those. Every image is built under NAME-new first;
# only when every asked image is built is each tag moved to it, and only then is each replaced image removed, by its ID.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
have() { docker image inspect "sci50f-rig:$1" >/dev/null 2>&1; }
one() { local d=( "$@" ); [ ${#d[@]} = 1 ] && [ -d "${d[0]}" ] || { echo "expected one folder: ${d[*]}" >&2; exit 1; }; echo "${d[0]}"; }
V=$(one stage/vtk9-*); P=$(one stage/paraview-*+stereo3d2); J=$(one stage/jmol-*); M=$(one stage/stereo-matplotlib-*)
R=; ls -d ref/vtk9-* >/dev/null 2>&1 && R=$(one ref/vtk9-*)
names="1 green-vtk green-pv2 green-i6b"; [ -n "$R" ] && names="$names pv2-ref"
case "${1:-}" in
  "") ask=; for n in $names; do have $n || ask="$ask $n"; done ;;
  all) ask=$names ;;
  *) ask="$*" ;;
esac
echo "making:${ask:- nothing}; vtk9 $V; ref ${R:-none}"
made=
src() { case " $ask " in *" $1 "*) echo sci50f-rig:$1-new ;; *) echo sci50f-rig:$1 ;; esac; }
SNAP=$(sed -n 's/^SNAP=${SNAP:-\(.*\)}$/\1/p' rig/prelude.sh)
snap_of() { scripts/drun.sh snapof "$1" --network none --cpus 1 -- cat /etc/apt/sci50f-snapshot 2>/dev/null || true; }
for n in $ask; do
  # an image NAME-new of the same instant, left by a run that stopped later, is taken as built
  if have $n-new && [ "$(snap_of sci50f-rig:$n-new)" = "$SNAP" ]; then echo "reusing sci50f-rig:$n-new ($SNAP)"; made="$made $n"; continue; fi
  case $n in
    1) rig/make-rig.sh 1-new ;;
    green-vtk) FROM=$(src 1) STAGE="$V" PKGS="libvtk9.6 libvtk9.6-qt" TAG=green-vtk-new rig/make-green.sh ;;
    green-pv2) FROM=$(src green-vtk) STAGE="$V $P" PKGS="libvtk9.6 libvtk9.6-qt python3-vtk9 paraview python3-paraview" TAG=green-pv2-new rig/make-green.sh ;;
    green-i6b) FROM=$(src 1) STAGE="$J $M" PKGS="jmol libjmol-java python3-stereo-matplotlib" TAG=green-i6b-new rig/make-green.sh ;;
    pv2-ref) FROM=$(src 1) STAGE="$R $P" PKGS="libvtk9.6 libvtk9.6-qt python3-vtk9 paraview python3-paraview" TAG=pv2-ref-new rig/make-green.sh ;;
    *) echo "unknown image $n" >&2; exit 1 ;;
  esac
  made="$made $n"
done
old=
for n in $made; do
  have $n && old="$(docker image inspect -f '{{.Id}}' sci50f-rig:$n) $old"
  docker tag sci50f-rig:$n-new sci50f-rig:$n && docker rmi sci50f-rig:$n-new >/dev/null
  echo "sci50f-rig:$n $(docker image inspect -f '{{.Id}}' sci50f-rig:$n)"
done
for id in $old; do docker rmi "$id" >/dev/null 2>&1 && echo "removed replaced image $id" || echo "kept replaced image $id: another image is built on it"; done
docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' | grep '^sci50f-'
