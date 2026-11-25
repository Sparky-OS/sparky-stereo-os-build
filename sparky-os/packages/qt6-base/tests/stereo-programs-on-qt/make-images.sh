#!/bin/bash
# make-images.sh WORKDIR -- row 863 part A's three images, under the tags its runners use:
#   sc50i-rig:a863-pub   sc50i-rig:fc-deb (the published tree r1123a over Debian testing at 20261123T203846Z, the
#                        published qt6-base +stereo3d23) with the published programs of part A by apt (the published
#                        tree at pin 1001, Debian's snapshot, deb-multimedia's own archive online: the lane's frozen copy
#                        holds only FreeCAD's needs), Qt's qml tool, and Calamares and its branding unpacked in /opt/r863
#                        (not installed: Calamares needs sparky-artwork, which neither the published tree nor Debian has)
#   sc50i-rig:a863-pubg  that with the published sparky-stereo-graphics (the control: the published set)
#   sc50i-rig:a863-q24   that with the staged qt6-base +stereo3d24 and sparky-stereo-graphics 0.2.18 by apt
#                        (qt-over.sh of the row 863 kit, from the stage's .deb files)
# apt's lines and the installed versions go to WORKDIR/images/TAG/.
set -euo pipefail
WORKDIR=$(readlink -f "$1"); mkdir -p "$WORKDIR"
L=/K3D/partners/queue/science-stereo-ship-and-upstream-50; K=/var/lib/sparky-lanes/science-50i/kept-freecad
export DOCKER_HOST=unix://$L/docker.sock
TAG=a863-pub; OUT=$WORKDIR/images/$TAG; rm -rf "$OUT"; mkdir -p "$OUT"
PKGS="kubrick kalgebra kalzium fraqtive krita vlc-stereo ffmpeg mkvtoolnix libstereo-layer1 qml6-module-qtquick qml6-module-qtquick-window"
POOL=/var/lib/sparky-lanes/sparky-repo-r1123a/pool/main
docker rm sc50i-mka863 > /dev/null 2>&1 || true
docker run --cidfile "$OUT/cid" --name sc50i-mka863 --pull=never --ulimit core=1 --cpus 4 -e "PKGS=$PKGS" \
  --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
  --mount type=bind,src=/K3D/partners/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly \
  --mount type=bind,src=$K/keys,dst=/run/keys,readonly --mount type=bind,src=$K/tools,dst=/tools,readonly \
  --mount type=bind,src=/var/lib/sparky-lanes/sparky-repo-r1123a,dst=/repo,readonly --mount type=bind,src=$POOL,dst=/pool,readonly \
  --mount type=bind,src=$OUT,dst=/out sc50i-rig:fc-deb bash -c '
  set -e
  . /tools/prelude-fc.sh > /dev/null 2>&1 || true
  printf "Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /run/keys/deb-multimedia-keyring.pgp\n" > /etc/apt/sources.list.d/dmo-online.sources
  apt-get update -qq 2>&1 | tail -3
  apt-cache policy $PKGS > /out/policy.txt 2>&1
  apt-get -s install $PKGS > /out/apt-sim.txt 2>&1
  grep -E "^(Inst|Remv)|upgraded" /out/apt-sim.txt > /out/apt-sim-lines.txt || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q $PKGS > /out/apt-install.txt 2>&1
  # Qt 6 QML runtime tool (Debian names it qml-qt6), for the installer slideshow in a window of its own
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q qml-qt6 >> /out/apt-install.txt 2>&1 || echo "qml-qt6 not installable" >> /out/apt-install.txt
  # the installer (Calamares) and its branding are unpacked, not installed: Calamares needs sparky-artwork, which neither
  # the published tree nor Debian has; only their QML (the slideshow module, show.qml and its pairs) is used
  mkdir -p /opt/r863 && dpkg-deb -x /pool/c/calamares/calamares_3.4.3~sparky9~4-1+stereo3d3+lc1_amd64.deb /opt/r863 \
    && dpkg-deb -x /pool/s/sparky-stereo-calamares-branding/sparky-stereo-calamares-branding_20261116~sparky9~0+lc1_all.deb /opt/r863
  dpkg --audit > /out/dpkg-audit.txt 2>&1; echo "dpkg --audit rc=$?" >> /out/dpkg-audit.txt
  dpkg-query -W $PKGS qml-qt6 libqt6widgets6 libqt6waylandclient6 kwin-wayland > /out/installed.txt 2>&1 || true
  ls /opt/r863/usr/share/calamares/qml/calamares/slideshow /opt/r863/usr/share/calamares/branding/sparky-stereo/show.qml >> /out/installed.txt 2>&1
  rm -f /etc/apt/sources.list.d/dmo-online.sources; apt-get clean'
docker commit sc50i-mka863 "sc50i-rig:$TAG" > /dev/null
grep -qx "sc50i-rig:$TAG" "$L/.artifacts" || echo "sc50i-rig:$TAG" >> "$L/.artifacts"
{ cat "$OUT/cid"; echo; } >> "$L/.container-ids"; rm -f "$OUT/cid"; docker rm sc50i-mka863 > /dev/null
echo "sc50i-rig:$TAG: $(grep -c '^Inst' "$OUT/apt-sim-lines.txt") Inst, $(grep -c '^Remv' "$OUT/apt-sim-lines.txt") Remv; $(tail -1 "$OUT/dpkg-audit.txt")"

# the published Graphics page (the published set's own)
O=$WORKDIR/images/a863-pubg; rm -rf "$O"; mkdir -p "$O"
docker run --cidfile "$O/cid" --name sc50i-mkag863 --pull=never --ulimit core=1 --cpus 4 \
  --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
  --mount type=bind,src=/K3D/partners/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly \
  --mount type=bind,src=$K/keys,dst=/run/keys,readonly --mount type=bind,src=$K/tools,dst=/tools,readonly \
  --mount type=bind,src=/var/lib/sparky-lanes/sparky-repo-r1123a,dst=/repo,readonly --mount type=bind,src=$O,dst=/out \
  sc50i-rig:a863-pub bash -c '. /tools/prelude-fc.sh > /dev/null 2>&1; apt-get -s -y --no-install-recommends install sparky-stereo-graphics > /out/apt-sim.txt 2>&1
  grep -E "^(Inst|Remv)" /out/apt-sim.txt > /out/apt-sim-lines.txt
  DEBIAN_FRONTEND=noninteractive apt-get -y -q --no-install-recommends install sparky-stereo-graphics > /out/apt-install.txt 2>&1; echo "install rc=$?" >> /out/apt-install.txt
  dpkg --audit > /out/dpkg-audit.txt 2>&1; echo "dpkg --audit rc=$?" >> /out/dpkg-audit.txt; dpkg-query -W sparky-stereo-graphics libqt6widgets6 > /out/installed.txt; apt-get clean'
docker commit sc50i-mkag863 sc50i-rig:a863-pubg > /dev/null
grep -qx sc50i-rig:a863-pubg "$L/.artifacts" || echo sc50i-rig:a863-pubg >> "$L/.artifacts"
{ cat "$O/cid"; echo; } >> "$L/.container-ids"; rm -f "$O/cid"; docker rm sc50i-mkag863 > /dev/null
echo "sc50i-rig:a863-pubg: $(grep -c '^Inst' "$O/apt-sim-lines.txt") Inst, $(grep -c '^Remv' "$O/apt-sim-lines.txt") Remv; $(tail -1 "$O/dpkg-audit.txt")"
# the staged Qt and Graphics over it
S=$WORKDIR/stage-debs; rm -rf "$S"; mkdir -p "$S"
cp /var/lib/sparky-lanes/qt-flush-863/stage/qt6-base/amd64/*.deb /var/lib/sparky-lanes/qt-flush-863/stage/sparky-stereo-graphics/*.deb "$S"/
R863_WORK=$WORKDIR bash /var/lib/sparky-lanes/qt-flush-863/kit/tools/qt-over.sh sc50i-rig:a863-pubg sc50i-rig:a863-q24 "$S" | tail -1
