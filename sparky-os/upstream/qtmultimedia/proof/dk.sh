#!/bin/bash
# usage: dk.sh <cmd...> : run in qtmm-build:1 as the user with /w = lane dir
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/w/home -e DEBIAN_FRONTEND=noninteractive -v ${SPARKY_SCRATCH:?}/qtmm-lane:/w -v ${SPARKY_REPO_DIR:?}:/repo:ro qtmm-build:1 bash -c "$*"
