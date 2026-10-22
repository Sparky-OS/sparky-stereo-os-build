#!/bin/bash
# usage: run-gen.sh <command...>  runs in the generator container (debian:testing + librsvg), workspace mounted at /w
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
exec timeout ${TMO:-3000} docker run --rm --name stereo-oxygen-gen-$$ -u $(id -u):$(id -g) -v ${SPARKY_WORKSPACES:?}/stereo-oxygen:/q -w /q/step1 stereo-oxygen-gen:1 "$@"
