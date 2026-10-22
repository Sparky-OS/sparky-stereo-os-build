#!/bin/bash
# usage: proof.sh <prefix> <image> [apps|tests|mono]...   the proof matrix on one image (native Wayland, headless KWin, Qt's own decorations)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
p=$1; img=$2; shift 2
cd ${SPARKY_SCRATCH:?}/qtgl/rig
export IMG=$img QTBUILD=${QTBUILD:-${SPARKY_SCRATCH:?}/qtgl/build-deb}
[ -n "$MYQT" ] && export MYQT=1
export NODECO='mkdir -p $XDG_CONFIG_HOME; printf "[org.kde.kdecoration2]\nNoPlugin=true\n" > $XDG_CONFIG_HOME/kwinrc'
FT=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1
what=${*:-apps tests mono}
for w in $what; do case $w in
apps)
  for i in 1 2; do ./kub.sh $p-kub-sw-$i SOFT=1 PRE="$NODECO" >/dev/null 2>&1; done
  ./kub.sh $p-kub-gpu PRE="$NODECO" >/dev/null 2>&1
  ./ka.sh $p-ka-sw SOFT=1 PRE="$NODECO" >/dev/null 2>&1
  ./ka.sh $p-ka-gpu PRE="$NODECO" >/dev/null 2>&1
  ./kz.sh $p-kz-sw SOFT=1 PRE="$NODECO" >/dev/null 2>&1
  ./kz.sh $p-kz-gpu PRE="$NODECO" >/dev/null 2>&1
  KZBIN=/deb/k2/usr/bin/kalzium ./kz.sh $p-kz-rev-sw SOFT=1 PRE="$NODECO" >/dev/null 2>&1
  KZBIN=/deb/k2/usr/bin/kalzium ./kz.sh $p-kz-rev-gpu PRE="$NODECO" >/dev/null 2>&1
  ;;
mono)
  # stereo off: the programs without --stereo, the demo frozen for Kubrick
  for i in 1 2; do env NAME=$p-kub-off-$i PRE="$NODECO" DETERMINISTIC=1 FAKETIME="2026-10-07 12:00:00" FREEZE_AT=60 FREEZE_SECONDS=14 WAIT=5 SHIM=$FT:/usr/local/lib/kubrick-shim.so CMD="/usr/games/kubrick" ./drun.sh >/dev/null 2>&1; done
  env NAME=$p-kub-off-gpu PRE="$NODECO" DETERMINISTIC=1 FAKETIME="2026-10-07 12:00:00" FREEZE_AT=60 FREEZE_SECONDS=14 WAIT=5 SHIM=$FT:/usr/local/lib/kubrick-shim.so CMD="/usr/games/kubrick" ./drun.sh >/dev/null 2>&1
  env NAME=$p-ka-off SOFT=1 PRE="$NODECO" WAIT=14 SHIM=/usr/local/lib/gl-shim.so INPUT="move 600 400 sleep 300 click sleep 500 keydown 0xffe9 keydown 0x33 keyup 0x33 keyup 0xffe9 sleep 2500" CMD="/usr/bin/kalgebra" ./drun.sh >/dev/null 2>&1
  env NAME=$p-ka-off-gpu PRE="$NODECO" WAIT=14 SHIM=/usr/local/lib/gl-shim.so INPUT="move 600 400 sleep 300 click sleep 500 keydown 0xffe9 keydown 0x33 keyup 0x33 keyup 0xffe9 sleep 2500" CMD="/usr/bin/kalgebra" ./drun.sh >/dev/null 2>&1
  env NAME=$p-kz-off SOFT=1 PRE="$NODECO" WAIT=16 SHIM=/usr/local/lib/gl-shim.so CMD="/usr/bin/kalzium -m /w/chain.xyz" ./drun.sh >/dev/null 2>&1
  env NAME=$p-kz-off-gpu PRE="$NODECO" WAIT=16 SHIM=/usr/local/lib/gl-shim.so CMD="/usr/bin/kalzium -m /w/chain.xyz" ./drun.sh >/dev/null 2>&1
  for m in none; do env NAME=$p-glw-$m QT_GLW_MODE=$m WAIT=6 PRE="$NODECO" CMD="/w/qt-glw-test" ./drun.sh >/dev/null 2>&1; env NAME=$p-glw-$m-sw SOFT=1 QT_GLW_MODE=$m WAIT=6 PRE="$NODECO" CMD="/w/qt-glw-test" ./drun.sh >/dev/null 2>&1; done
  env NAME=$p-plain WAIT=5 PRE="$NODECO" CMD="/usr/local/bin/qt-plain" ./drun.sh >/dev/null 2>&1
  ;;
tests)
  r() { n=$1; shift; env NAME=$p-glw-$n WAIT=7 PRE="$NODECO" CMD="/w/qt-glw-test" "$@" ./drun.sh >/dev/null 2>&1; }
  r default QT_GLW_MODE=default; r widget QT_GLW_MODE=widget; r widget-sw QT_GLW_MODE=widget SOFT=1; r toplevel QT_GLW_MODE=toplevel
  r nooverlay QT_GLW_MODE=widget QT_GLW_NOOVERLAY=1; r stacktop QT_GLW_MODE=widget QT_GLW_STACKTOP=1
  r resize QT_GLW_MODE=widget QT_GLW_SCENARIO=resize; r toolbar QT_GLW_MODE=widget QT_GLW_SCENARIO=toolbar
  r scroll QT_GLW_MODE=widget QT_GLW_SCENARIO=scroll; r tabs QT_GLW_MODE=widget QT_GLW_SCENARIO=tabs; r tabsback QT_GLW_MODE=widget QT_GLW_SCENARIO=tabs QT_GLW_TABBACK=1
  r dlg QT_GLW_MODE=default QT_GLW_DIALOG=1; r dlg-widget QT_GLW_MODE=widget QT_GLW_DIALOG=1
  r click QT_GLW_MODE=widget INPUT="move 380 300 sleep 300 click sleep 500 move 700 500 sleep 200 click sleep 500"
  r xcb PLAT=xcb QT_GLW_MODE=default
  ;;
esac; done
echo PROOF_DONE $p
