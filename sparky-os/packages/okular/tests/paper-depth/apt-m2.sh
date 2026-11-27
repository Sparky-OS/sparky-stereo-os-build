#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# apt-m2.sh IMAGE REPO STAGE_M1 STAGE_M2 RESULTS
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
image=$1 repo=$(realpath "$2") m1=$(realpath "$3") m2=$(realpath "$4")
out=$(mkdir -p "$5" && cd "$5" && pwd -P)
name=${PREFIX:?use the lane prefix}-apt
docker run --name "$name" --pull=never --platform linux/amd64 --ulimit core=1 --cpus 2 \
    --add-host repo.sparkyos.org:127.0.0.1 --add-host d2server:127.0.0.1 \
    --mount "type=bind,src=$repo,dst=/repo,readonly" \
    --mount "type=bind,src=$m1,dst=/m1,readonly" --mount "type=bind,src=$m2,dst=/m2,readonly" \
    --mount "type=bind,src=$out,dst=/out" \
    --mount "type=bind,src=$here/../../../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    --mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    "$image" bash -ec '
export DEBIAN_FRONTEND=noninteractive
trap "chown -R 1000:1000 /out" EXIT
sh /run/https-only-apt.sh
cp /repo/sparky-stereo-repo.asc /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
printf "deb [signed-by=/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc] file:/repo mashtabba main\n" > /etc/apt/sources.list.d/edition.list
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/edition
apt-get -qq update
apt-get -y --no-install-recommends install kwin-wayland okular calligrawords sparky-stereo-graphics apt-utils > /out/before-install.log 2>&1
rm -f /etc/apt/sources.list.d/sparky-stereo.sources
dpkg-query -W kwin-wayland kwin-common libkwin6 libqt6waylandclient6 sparky-stereo-graphics calligrawords > /out/before-versions.txt
make_repository() {
    local candidate=$1; shift
    mkdir -p "$candidate"
    for dir in "$@"; do
        find "$dir" -maxdepth 1 -name "*.deb" ! -name "*-dbgsym_*" -exec cp {} "$candidate/" \;
    done
    (
        cd "$candidate"
        apt-ftparchive packages . > Packages
        apt-ftparchive -o "APT::FTPArchive::Release::Origin=Sparky Stereo OS" release . > Release
    )
}
make_repository /candidate-red /m1/qt6-base /m1/sparky-stereo-graphics /m2/kwin
make_repository /candidate-green /m2/qt6-base /m2/kwin /m2/sparky-stereo-graphics /m2/plasma-wayland-protocols /m2/calligra /m1/okular
for row in red green; do
    printf "deb [trusted=yes] file:/candidate-%s ./\n" "$row" > /etc/apt/sources.list.d/candidate.list
    apt-get -qq update
    apt-cache policy kwin-wayland libkwin6 libqt6waylandclient6 sparky-stereo-graphics calligrawords > "/out/$row-policy.txt"
    case $row in red) qt=25 ;; green) qt=26 ;; esac
    apt-get -s --no-remove install "libqt6waylandclient6=6.11.2+dfsg-5+stereo3d$qt+lc1" > "/out/$row-qt-only.txt" 2>&1
    grep -q "^Inst libqt6waylandclient6 .*+stereo3d$qt+lc1" "/out/$row-qt-only.txt"
done
! grep -qE "^Inst (kwin-wayland|libkwin6) " /out/red-qt-only.txt
grep -q "^Inst kwin-wayland .*stereo3d70+lc1" /out/green-qt-only.txt
grep -q "^Inst libkwin6 .*stereo3d70+lc1" /out/green-qt-only.txt
apt-get -s --no-remove full-upgrade > /out/green-full-upgrade.txt 2>&1
grep -q "^Inst kwin-wayland .*stereo3d70+lc1" /out/green-full-upgrade.txt
grep -q "^Inst libqt6waylandclient6 .*stereo3d26+lc1" /out/green-full-upgrade.txt
grep -q "^Inst calligrawords .*stereo3d1+lc1" /out/green-full-upgrade.txt
'
docker inspect -f '{{.Id}}' "$name" >> "${CIDS:-/dev/null}"
docker rm "$name" > /dev/null
