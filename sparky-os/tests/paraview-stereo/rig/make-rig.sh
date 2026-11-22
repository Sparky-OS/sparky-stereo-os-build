#!/bin/bash
# make-rig.sh [TAG]  -- the rig image sci50f-rig:TAG (default 1): the base debian:testing image (amd64, 2026-11-04, 7b0e755eb7e3)
# with Debian testing taken from snapshot.debian.org at one instant (rig/prelude.sh, SNAP, default 20261119T023717Z, see
# rig/SNAPSHOT.md) and brought up to it with dist-upgrade, deb-multimedia from its frozen signed index ($S/frozen/dmo), the
# published edition tree r1118a at pin 1001 (Stereo KWin, Mesa, Xwayland), libstereo-declare1 and python3-stereo-declare
# 1.12.1 (copies in $S/frozen/sd, with lane 750e's sums), Debian's own jmol, paraview and python3-matplotlib (Tk and Qt
# backends), the capture and driving tools, five locales and CJK fonts. apt's dist-upgrade simulation of the finished image
# goes to runs/apt-distupgrade-TAG.txt; it must say 0 upgraded and 0 not upgraded.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
TAG=${1:-1}; C=sci50f-mkrig-$$
gone() { docker inspect -f '{{.Id}}' $C >> $L/.container-ids 2>/dev/null && docker rm -f $C >/dev/null 2>&1 || true; }
trap gone EXIT
BASE=sha256:7b0e755eb7e3569feb5936ce244a10e3b6e77c9e5dd2a89cdb30e382d1b48e2e
docker run --name $C --pull=never --ulimit core=1 --cpus ${RIG_CPUS:-4} --platform linux/amd64 -e SNAP=${SNAP:-20261119T023717Z} \
  -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
  -v $S/keys:/run/keys:ro -v $S/rig:/rig:ro -v $S/frozen/dmo:/dmo:ro -v $S/frozen/sd:/sd:ro -v $S/runs:/runs \
  -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro \
  $BASE sh -c '
  set -e
  . /rig/prelude.sh
  apt-get -y -q dist-upgrade > /tmp/du.log 2>&1 || { tail -30 /tmp/du.log; exit 1; }
  apt-get install -y -q --no-install-recommends kwin-wayland xwayland libgl1-mesa-dri libegl-mesa0 libglx-mesa0 mesa-vulkan-drivers \
    dbus dbus-x11 xdotool x11-utils x11-xserver-utils xvfb xauth procps locales python3 python3-xlib python3-pil python3-numpy \
    python3-gi gir1.2-glib-2.0 fonts-dejavu-core fonts-noto-cjk mesa-utils gdb gettext-base \
    jmol default-jre paraview python3-matplotlib python3-tk python3-pyqt6 qt6-wayland \
    /sd/libstereo-declare1_1.12.1-1+lc1_amd64.deb /sd/python3-stereo-declare_1.12.1-1+lc1_all.deb > /tmp/inst.log 2>&1 || { tail -30 /tmp/inst.log; exit 1; }
  # libstereo-declare 1.12.1 (the copies in frozen/sd, as step 3 used) is newer than 1.10.0 of r1118a, which pin 1001 would
  # bring back at the next dist-upgrade: this one version is pinned above it
  printf "Package: libstereo-declare1 python3-stereo-declare\nPin: version 1.12.1-1+lc1\nPin-Priority: 1002\n" > /etc/apt/preferences.d/10-sci50f-stereo-declare
  useradd -u 1000 -m -s /bin/bash rig
  for l in en_US de_DE pt_BR ja_JP fr_FR; do sed -i "s/^# *\($l.UTF-8 UTF-8\)/\1/" /etc/locale.gen; done; locale-gen > /dev/null
  mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix
  { echo "snapshot $(cat /etc/apt/sci50f-snapshot)"; grep -h -m1 "^Date" /var/lib/apt/lists/*_dists_testing_InRelease | sed "s/^/testing index /";
    apt-get -s dist-upgrade | grep -E "^(Inst|Remv)|upgraded"; } > /runs/apt-distupgrade-'"$TAG"'.txt
  chown 1000:1000 /runs/apt-distupgrade-'"$TAG"'.txt; cat /runs/apt-distupgrade-'"$TAG"'.txt
  dpkg-query -W kwin-wayland xwayland libgl1-mesa-dri libstereo-declare1 python3-stereo-declare jmol default-jre paraview python3-matplotlib python3-pyqt6 openjdk-25-jre libvtk9.6
  apt-get clean'
docker commit $C sci50f-rig:$TAG >/dev/null
grep -qx sci50f-rig:$TAG $L/.artifacts || echo sci50f-rig:$TAG >> $L/.artifacts
docker image inspect -f '{{.Id}} {{.Size}}' sci50f-rig:$TAG
