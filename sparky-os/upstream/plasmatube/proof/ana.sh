#!/bin/sh
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -e SW_W=${SW_W:-1280} -v ${SPARKY_WORKSPACES:?}/plasmatube:/w -v ${SPARKY_WORKSPACES:?}/players-stereo/.scratch/run:/p:ro ${IMG:-pt-run:A} sh -c "python3 /w/run/ana.py /w/out/$1/c*.png"
