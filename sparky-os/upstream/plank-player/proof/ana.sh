#!/bin/sh
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -e SW_W=${SW_W:-1280} -v /K3D/temp/partners/queue/plank-player:/w -v /K3D/temp/partners/queue/players-stereo/.scratch/run:/p:ro ${IMG:-plank-run:A} sh -c "python3 /w/run/ana.py /w/out/$1/c*.png"
