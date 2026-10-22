#!/bin/bash
# usage: NAME=.. CMD=".." [env] drun.sh
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
exec docker run --rm --platform linux/amd64 --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 -u $(id -u):$(id -g) \
 -e NAME -e CMD -e WAIT -e SW -e SH -e INPUT -e SHIM -e SOFT -e PLAT -e PRE -e SETTLE -e QT_LOGGING_RULES -e QT_WAYLAND_DEBUG -e KUBRICK_DEBUG -e SSH_ASKPASS_REQUIRE=never -e FREEZE_AT -e FREEZE_SECONDS -e STATIC_ONLY -e GEOM_EVERY -e DETERMINISTIC -e LD_LIBRARY_PATH -e XDG_DATA_DIRS -e FAKETIME -e QT_ENV \
 -v ${SPARKY_WORKSPACES:?}/kde-science-camera/work/passwd:/etc/passwd:ro -v ${SPARKY_SCRATCH:?}/kdesci-wl/deb:/deb:ro -v ${SPARKY_SCRATCH:?}/kdesci-wl:/w -v ${SPARKY_SCRATCH:?}/kdesci-wl/ev:/ev ${IMG:-kdesci-wl:1} /w/run.sh
