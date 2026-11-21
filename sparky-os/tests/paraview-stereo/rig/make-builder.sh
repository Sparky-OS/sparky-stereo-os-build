#!/bin/bash
# make-builder.sh -- the builder image sci50f-builder:1: debian:testing (amd64, image 7b0e755eb7e3, 2026-11-04) upgraded to
# today's testing, with the build dependencies of Debian testing's vtk9 9.6.2+ds-3, the recipe tools (devscripts, fakeroot,
# dpkg-dev, apt-utils) and what the Lean Code steps call (bubblewrap, clang, nodejs, node-acorn, python3-yaml, perl). No
# edition pin: vtk9 builds against Debian's own libraries, as Debian's build does. ParaView's build dependencies (Debian's
# libvtk9-dev among them) are not in this image; its build installs them in its own container.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
BASE=sci50f-base:testing-20261104
docker rm sci50f-mkbuilder >/dev/null 2>&1 || true
docker run --name sci50f-mkbuilder --pull=never --ulimit core=1 --cpus 4 --platform linux/amd64 \
  -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
  $BASE sh -c '
  set -e
  sh /run/https-only-apt.sh >/dev/null; export DEBIAN_FRONTEND=noninteractive
  sed -i "s/^Types: deb$/Types: deb deb-src/" /etc/apt/sources.list.d/debian.sources
  apt-get update -qq
  apt-get -y -q dist-upgrade > /tmp/du.log 2>&1 || { tail -30 /tmp/du.log; exit 1; }
  apt-get build-dep -y -q --no-install-recommends vtk9=9.6.2+ds-3 > /tmp/bd.log 2>&1 || { tail -30 /tmp/bd.log; exit 1; }
  apt-get install -y -q --no-install-recommends devscripts fakeroot apt-utils dpkg-dev build-essential bubblewrap clang nodejs \
    node-acorn python3-yaml python3 perl git ca-certificates equivs > /tmp/inst.log 2>&1 || { tail -30 /tmp/inst.log; exit 1; }
  dpkg-query -W -f "\${Package} \${Version}\n" gcc g++ cmake dpkg-dev debhelper default-jdk python3 qt6-base-dev libopenmpi-dev \
    libhdf5-openmpi-dev bubblewrap clang nodejs node-acorn devscripts dwz binutils
  apt-get clean; rm -rf /var/lib/apt/lists/*'
docker commit sci50f-mkbuilder sci50f-builder:1 >/dev/null
grep -qx sci50f-builder:1 $L/.artifacts || echo sci50f-builder:1 >> $L/.artifacts
docker inspect -f '{{.Id}}' sci50f-mkbuilder >> $L/.container-ids
docker rm sci50f-mkbuilder >/dev/null
docker image inspect -f '{{.Id}} {{.Size}}' sci50f-builder:1
