#!/bin/sh
# usage: ana360.sh <360|180> <clip file in clips/> <run name>
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -e CX -e CY -e SW_W=${SW_W:-1280} -v ${SPARKY_WORKSPACES:?}/plasmatube:/w ${IMG:-pt-run:C} sh -c "python3 /w/run/ana360.py $1 /w/clips/$2 /w/out/$3/c*.png"
