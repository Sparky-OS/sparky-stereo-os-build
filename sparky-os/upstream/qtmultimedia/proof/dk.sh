#!/bin/bash
# usage: dk.sh <cmd...> : run in qtmm-build:1 as the user with /w = lane dir
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/w/home -e DEBIAN_FRONTEND=noninteractive -v /K3D/temp/qtmm-lane:/w -v /K3D/temp/sparky-os/repo:/repo:ro qtmm-build:1 bash -c "$*"
