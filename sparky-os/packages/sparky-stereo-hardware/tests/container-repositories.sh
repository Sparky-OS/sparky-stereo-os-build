#!/bin/bash
set -euo pipefail
[[ -e /.dockerenv ]] || { echo "Run in Docker only"; exit 1; }
exec >evidence/repositories.log 2>&1
export DEBIAN_FRONTEND=noninteractive
sed -i 's/Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
curl --fail --location --max-time 30 https://repo.sparkylinux.org/sparky.gpg.key -o /usr/share/keyrings/sparky.gpg.key
printf '%s\n' 'deb [signed-by=/usr/share/keyrings/sparky.gpg.key] https://repo.sparkylinux.org/ core main' >/etc/apt/sources.list.d/sparky.list
apt-get -y update
apt-get -y --no-install-recommends install sparky-remsu sparky-xterm nvidia-detect
printf 'REPOSITORIES COMPLETE\n'
