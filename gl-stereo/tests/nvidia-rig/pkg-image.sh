#!/bin/sh
# usage: pkg-image.sh TAG DEBDIR...  -- a fresh container from the lane image with the staged debs installed (apt-get install ./x.deb)
export DOCKER_HOST=unix:///K3D/partners/queue/nvidia-gl-stereo-146b/docker.sock
TAG=$1; shift
M=""; for d in "$@"; do M="$M -v $d:/debs/$(basename $d):ro"; done
docker rm -f nvidia-gl-stereo-146b-pkginst >/dev/null 2>&1
docker run --name nvidia-gl-stereo-146b-pkginst --ulimit core=0 --add-host repo.sparkyos.org:192.168.0.60 \
  -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro $M \
  nvidia-gl-stereo-146b-rig:3 sh -c '
    sh /run/https-only-apt.sh && apt-get update -qq
    # the runtime packages of the staged sets that are already installed, at the staged version
    debs=""
    for f in /debs/*/*.deb; do
      case $f in *-dbgsym_*|*-lc-hr_*) continue;; esac
      n=$(dpkg-deb -f $f Package); a=$(dpkg-deb -f $f Architecture)
      if dpkg -s $n >/dev/null 2>&1; then debs="$debs $f"; fi
    done
    echo "installing: $debs" | tr " " "\n" | sed "s|/debs/[^/]*/||" | head -60
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install $debs 2>&1 | tail -5
  ' && docker commit nvidia-gl-stereo-146b-pkginst "$TAG" >/dev/null && docker rm nvidia-gl-stereo-146b-pkginst >/dev/null && echo "$TAG" >> /K3D/partners/queue/nvidia-gl-stereo-146b/.artifacts && echo image "$TAG"
