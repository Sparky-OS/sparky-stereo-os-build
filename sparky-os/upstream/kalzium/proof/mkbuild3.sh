#!/bin/bash
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get build-dep -y avogadrolibs kalzium 2>&1 | tail -2
