#!/bin/bash
# usage: run-gen.sh <command...>  runs in the generator container (debian:testing + librsvg), workspace mounted at /w
exec timeout ${TMO:-3000} docker run --rm --name stereo-oxygen-gen-$$ -u $(id -u):$(id -g) -v /K3D/temp/partners/queue/stereo-oxygen:/q -w /q/step1 stereo-oxygen-gen:1 "$@"
