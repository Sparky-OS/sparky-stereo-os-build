#!/bin/bash
# usage: NAME=.. CMD=".." [env] drun.sh   (IMG=qtgl-run:before|after|control; MYQT=1 uses the dev build in /qtbuild)
mkdir -p /K3D/temp/qtgl/ev
exec docker run --rm --platform linux/amd64 --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 -u $(id -u):$(id -g) \
 -e NAME -e CMD -e WAIT -e SW -e SH -e INPUT -e SHIM -e SOFT -e PLAT -e PRE -e SETTLE -e QT_LOGGING_RULES -e QT_WAYLAND_DEBUG -e KUBRICK_DEBUG -e SSH_ASKPASS_REQUIRE=never -e FREEZE_AT -e FREEZE_SECONDS -e STATIC_ONLY -e GEOM_EVERY -e DETERMINISTIC -e LD_LIBRARY_PATH -e XDG_DATA_DIRS -e FAKETIME -e QT_ENV -e TESTARGS -e MYQT -e QT_GLW_MODE -e QT_GLW_NOOVERLAY -e QT_GLW_STACKTOP -e QT_GLW_DIALOG -e QT_GLW_NOSIBLINGS -e QT_GLW_ALPHA -e QT_GLW_SCENARIO -e QT_GLW_TABBACK -e QT_GLW_ANC -e PRE -e EXTRA_ENV \
 -v /K3D/temp/partners/queue/kde-science-camera/work/passwd:/etc/passwd:ro -v /K3D/temp/qtgl/deb:/deb:ro -v /K3D/temp/qtgl/rig:/w -v /K3D/temp/qtgl/ev:/ev -v ${QTBUILD:-/K3D/temp/qtgl/build}:/qtbuild:ro ${IMG:-qtgl-run:before} /w/run.sh
