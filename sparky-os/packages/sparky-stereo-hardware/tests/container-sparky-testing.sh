#!/bin/bash
set -euo pipefail
[[ -e /.dockerenv ]] || { echo "Run in Docker only"; exit 1; }
exec >>evidence/repositories.log 2>&1
export DEBIAN_FRONTEND=noninteractive
printf '%s\n' 'deb [signed-by=/usr/share/keyrings/sparky.gpg.key] https://repo.sparkylinux.org/ tiamat main' >>/etc/apt/sources.list.d/sparky.list
apt-get -y update
apt-get -y --no-install-recommends install sparky-remsu sparky-xterm nvidia-detect
printf 'REPOSITORIES COMPLETE\n'
