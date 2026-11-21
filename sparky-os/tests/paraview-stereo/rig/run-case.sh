#!/bin/bash
# usage: run-case.sh NAME IMAGE CASE.sh [VAR=value ...]   -- one fresh container and Stereo KWin session per case
# GPU=nvidia gives the RTX 3060 through CDI with the session's own zink route for the program (sparky-stereo-hardware's
# environment, set here as that script sets it); default: the AMD render node.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
name=$1 image=$2 case=$3; shift 3
out=$S/runs/$name; rm -rf "$out"; mkdir -p "$out"
envs=(); for kv in "$@"; do envs+=(-e "$kv"); done
mounts=(); for m in ${MOUNTS:-}; do mounts+=(-v "$m:ro"); done
if [ "${GPU:-amd}" = nvidia ]; then
  gpu=(--device nvidia.com/gpu=0 -e "CASE_ENV=__GLX_VENDOR_LIBRARY_NAME=mesa MESA_LOADER_DRIVER_OVERRIDE=zink LIBGL_KOPPER_DISABLE=1 __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json:/usr/share/glvnd/egl_vendor.d/10_nvidia.json")
else
  gpu=(--device /dev/dri/renderD128 --group-add 125)
fi
cid=$S/runs/.cid-$$; rm -f $cid
docker run --rm --name sci50f-case-$$ --cidfile $cid --pull=never --ulimit core=1 --cpus 4 --platform linux/amd64 --network none \
  --cap-add SYS_NICE "${gpu[@]}" --user 1000:1000 -v $S/rig:/rig:ro -v $S/fixtures:/fixtures:ro -v $out:/out "${mounts[@]}" "${envs[@]}" \
  "$image" bash /rig/${SESSION:-session.sh} /out bash /rig/$case > $out/case.log 2>&1 || echo "case rc=$?" >> $out/case.log
cat $cid >> $L/.container-ids; echo >> $L/.container-ids; rm -f $cid
tail -3 $out/case.log
