#!/bin/bash
# a6-images.sh BASE TAG -- row 863 part A6: TAG from BASE (sc50i-rig:oct863-pkg-doc2, the Octave of step 5b's stage on
# the published Qt, which stays as it is) with an X server for Octave's 2D-screen row: xvfb and python3-xlib (the rig's
# xshot.py) from Debian testing at snapshot 20261119T023717Z, the instant the Octave kit's images were made against
# (Debian's archive only, over https). apt's lines go to ${R863_WORK:-/var/tmp/qt-flush-863/parta}/images/TAG/.
set -euo pipefail
L=/K3D/partners/queue/science-stereo-ship-and-upstream-50
export DOCKER_HOST=unix://$L/docker.sock
BASE=$1 TAG=$2; OUT=${R863_WORK:-/var/tmp/qt-flush-863/parta}/images/${TAG//[:\/]/_}; rm -rf "$OUT"; mkdir -p "$OUT"
docker run --cidfile "$OUT/cid" --name sc50i-a6img --pull=never --ulimit core=1 --cpus 4 \
  --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
  --mount type=bind,src=/K3D/partners/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly \
  --mount type=bind,src=$OUT,dst=/out "$BASE" bash -c '
  set -e
  mkdir -p /tmp/src.d
  printf "Types: deb\nURIs: https://snapshot.debian.org/archive/debian/20261119T023717Z\nSuites: testing\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nCheck-Valid-Until: no\n" > /tmp/src.d/snap.sources
  A=(-o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=/tmp/src.d -o Acquire::Retries=5)
  sh /run/https-only-apt.sh > /dev/null 2>&1 || true
  apt-get "${A[@]}" update -qq 2>&1 | tail -2
  apt-get "${A[@]}" -s -y --no-install-recommends install xvfb python3-xlib > /out/apt-sim.txt 2>&1
  grep -E "^(Inst|Remv)" /out/apt-sim.txt > /out/apt-sim-lines.txt || true
  DEBIAN_FRONTEND=noninteractive apt-get "${A[@]}" -y -q --no-install-recommends install xvfb python3-xlib > /out/apt-install.txt 2>&1
  echo "install rc=$?" >> /out/apt-install.txt
  dpkg --audit > /out/dpkg-audit.txt 2>&1; echo "dpkg --audit rc=$?" >> /out/dpkg-audit.txt
  dpkg-query -W xvfb python3-xlib octave libqt6widgets6 > /out/installed.txt 2>&1 || true
  apt-get clean; rm -rf /var/lib/apt/lists/*snapshot*'
docker commit sc50i-a6img "$TAG" > /dev/null
echo "$TAG" >> "$L/.artifacts"
{ cat "$OUT/cid"; echo; } >> "$L/.container-ids"
docker rm sc50i-a6img > /dev/null
echo "$TAG from $BASE: $(grep -c '^Inst' "$OUT/apt-sim-lines.txt") Inst, $(grep -c '^Remv' "$OUT/apt-sim-lines.txt") Remv; $(tail -1 "$OUT/dpkg-audit.txt")"
