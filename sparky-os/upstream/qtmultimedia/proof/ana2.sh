#!/bin/sh
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -e SW_W=${SW_W:-1280} -e CROP_TOP=${CROP_TOP:-0} -e NO_BAR=${NO_BAR:-} -v ${SPARKY_SCRATCH:?}/qtmm-lane:/w -v ${SPARKY_WORKSPACES:?}/players-stereo/.scratch/run:/p:ro qtmm-run:2 sh -c "python3 /w/run/ana2.py /w/out/$1/c*.png"
