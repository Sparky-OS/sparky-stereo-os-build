#!/bin/sh
# usage: ana360.sh <360|180> <clip file in clips/> <run name>
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -e CX -e CY -e SW_W=${SW_W:-1280} -v /K3D/temp/partners/queue/plasmatube:/w ${IMG:-pt-run:C} sh -c "python3 /w/run/ana360.py $1 /w/clips/$2 /w/out/$3/c*.png"
