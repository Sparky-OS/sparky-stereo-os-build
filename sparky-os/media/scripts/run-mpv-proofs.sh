#!/bin/bash
# usage: run-mpv-proofs.sh <image> <prefix> [parts]   parts: any of  m (matrix on three outputs), e (EGL contexts), p (placement), i (interpolation)
# Runs the proof rig of the players-stereo lane (rounds 2 and 3) against the mpv in <image>. Two runs at a time, two CPUs each.
cd /K3D/temp/partners/queue/media-on-dmo/work/rig
img=$1; pre=$2; parts=${3:-mepi}
export JOBS=${JOBS:-2} CPUS=${CPUS:-2}
if [[ $parts == *m* ]]; then
  for vo in dmabuf-wayland gpu-next gpu; do
    tag=$vo; [ $vo = dmabuf-wayland ] && tag=dmabuf; [ $vo = gpu-next ] && tag=gn
    echo "== matrix $vo $(date +%T)"; scripts/matrix.sh $pre-$tag $img $vo
  done
fi
if [[ $parts == *e* ]]; then
  for vo in gpu-next gpu; do
    tag=gn; [ $vo = gpu ] && tag=gpu
    echo "== EGL $vo $(date +%T)"
    EXTRA="--gpu-api=opengl --gpu-context=wayland" ONLY='^(ord-sbs-L-g12.mp4|ord-sbs-L-g12.mkv|hevc-sbs-L-g12.mp4|hevc-cat-3d2d.mp4|x265-cat-3d2d.mp4|cat-3d2d.mp4|cancel-60.mp4|ord-2d.mp4):' scripts/matrix.sh $pre-egl-$tag $img $vo
  done
fi
if [[ $parts == *p* ]]; then echo "== placement $(date +%T)"; scripts/f2matrix.sh $pre-place $img; fi
if [[ $parts == *i* ]]; then echo "== interpolation $(date +%T)"; scripts/imatrix.sh $pre-interp $img; fi
echo "== done $(date +%T)"
