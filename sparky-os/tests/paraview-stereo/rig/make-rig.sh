#!/bin/bash
# make-rig.sh -- (copied from lane 50e and adapted) the rig image sci50f-rig:1: debian:testing (amd64, 2026-11-04, image 7b0e755eb7e3) with the published
# edition tree r1118a at pin 1001 (Stereo KWin, Mesa, Xwayland), libstereo-declare1 and python3-stereo-declare 1.12.1
# (lane 750e's stage, as step 3 used), Debian's own jmol, paraview and python3-matplotlib (Tk and Qt backends), the
# capture and driving tools, four locales and CJK fonts.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
BASE=sha256:7b0e755eb7e3569feb5936ce244a10e3b6e77c9e5dd2a89cdb30e382d1b48e2e
docker rm -f sci50f-mkrig >/dev/null 2>&1 || true
docker run --name sci50f-mkrig --pull=never --ulimit core=1 --cpus ${RIG_CPUS:-4} --platform linux/amd64 \
  -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
  -v $S/keys:/run/keys:ro -v $S/rig:/rig:ro \
  -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro -v /mnt/build/one-separation-outputs-750e/stage/stereo-declare:/sd:ro \
  $BASE sh -c '
  set -e
  . /rig/prelude.sh
  apt-get install -y -q --no-install-recommends kwin-wayland xwayland libgl1-mesa-dri libegl-mesa0 libglx-mesa0 mesa-vulkan-drivers \
    dbus dbus-x11 xdotool x11-utils x11-xserver-utils xvfb xauth procps locales python3 python3-xlib python3-pil python3-numpy \
    python3-gi gir1.2-glib-2.0 fonts-dejavu-core fonts-noto-cjk mesa-utils gdb gettext-base \
    jmol default-jre paraview python3-matplotlib python3-tk python3-pyqt6 qt6-wayland \
    /sd/libstereo-declare1_1.12.1-1+lc1_amd64.deb /sd/python3-stereo-declare_1.12.1-1+lc1_all.deb > /tmp/inst.log 2>&1 || { tail -30 /tmp/inst.log; exit 1; }
  useradd -u 1000 -m -s /bin/bash rig
  for l in en_US de_DE pt_BR ja_JP fr_FR; do sed -i "s/^# *\($l.UTF-8 UTF-8\)/\1/" /etc/locale.gen; done; locale-gen > /dev/null
  mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix
  dpkg-query -W kwin-wayland xwayland libgl1-mesa-dri libstereo-declare1 python3-stereo-declare jmol default-jre paraview python3-matplotlib python3-pyqt6 openjdk-25-jre
  apt-get clean'
docker commit sci50f-mkrig sci50f-rig:1 >/dev/null
grep -qx sci50f-rig:1 $L/.artifacts || echo sci50f-rig:1 >> $L/.artifacts
docker inspect -f '{{.Id}}' sci50f-mkrig >> $L/.container-ids; docker rm sci50f-mkrig >/dev/null
docker image inspect -f '{{.Id}} {{.Size}}' sci50f-rig:1
