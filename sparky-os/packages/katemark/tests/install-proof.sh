#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# The staged package installed by apt in a clean debian:testing container with the edition's published round at pin 1001 (ORDER 51):
# apt's plan (Inst and Remv lines), the real install, the files, the plugin's libraries, Kate finding the plugin, purge, nothing left.
# Usage: install-proof.sh BASE_IMAGE REPO STAGE OUTDIR   (apt downloads over https; Kate runs offscreen with no network is not needed here: see proof.sh)
set -euo pipefail
BASE=${1:?base image} REPO=$(realpath "${2:?edition repository}") STAGE=$(realpath "${3:?stage}") OUT=$(realpath -m "${4:?output folder}")
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT" && chmod 777 "$OUT"
docker run --ulimit core=1 --pull=never --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}katemark-install" --platform linux/amd64 --cpus 4 \
	-v "$REPO":/repo:ro -v "$STAGE":/stage:ro -v "$OUT":/out \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$BASE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf "Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/sparky.sources
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/sparky
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install deb-multimedia-keyring >/dev/null
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
apt-get -y update >/dev/null
apt-get -y install dpkg-dev >/dev/null
mkdir /tmp/flat && cp /stage/katemark_*.deb /tmp/flat/ && (cd /tmp/flat && dpkg-scanpackages . > Packages 2>/dev/null)
printf "Types: deb\nURIs: file:/tmp/flat\nSuites: ./\nTrusted: yes\n" > /etc/apt/sources.list.d/stage.sources
printf "Package: katemark\nPin: origin \"\"\nPin-Priority: 1002\n" > /etc/apt/preferences.d/stage
apt-get -y update >/dev/null
dpkg-query -W -f "\${Package} \${Version}\n" | sort > /out/before.txt
apt-get -s install katemark > /out/apt-simulate.txt
apt-get -y install katemark > /out/apt-install.txt 2>&1
dpkg-query -W -f "\${Package} \${Version}\n" | sort > /out/after.txt
dpkg -s katemark > /out/dpkg-status.txt
dpkg -L katemark | grep -v "/locale/" > /out/files-installed.txt
dpkg -L katemark | grep -c "/locale/" > /out/locale-files-count.txt
so=/usr/lib/x86_64-linux-gnu/qt6/plugins/kf6/ktexteditor/katemark.so
ldd -r $so > /out/ldd.txt 2>&1 || true
apt-cache policy katemark kate qt6-base-dev > /out/policy.txt
QT_QPA_PLATFORM=offscreen QT_LOGGING_RULES="kf.coreaddons.debug=true" timeout 20 kate -n --help > /out/kate-help.txt 2>&1 || true
dpkg --verify katemark > /out/dpkg-verify.txt 2>&1 || true
apt-get -y purge katemark > /out/apt-purge.txt 2>&1
dpkg -L katemark > /out/files-after-purge.txt 2>&1 || true
dpkg -s katemark > /out/dpkg-status-after-purge.txt 2>&1 || true
ls -d /usr/share/doc/katemark /usr/lib/x86_64-linux-gnu/qt6/plugins/kf6/ktexteditor/katemark.so /usr/share/locale/pt_BR/LC_MESSAGES/katemark.mo /var/lib/dpkg/info/katemark.* /etc/katemark* > /out/leftovers.txt 2>&1 || true
dpkg-query -W -f "\${Package} \${Version}\n" | sort > /out/after-purge.txt
dpkg -l | grep -i katemark > /out/dpkg-l-after-purge.txt || true
'
