#!/bin/bash
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get build-dep -y analitza kalgebra 2>&1 | tail -2
apt-get install -y --no-install-recommends qt6-wayland xdotool 2>&1 | tail -1
