cd /K3D/temp/qtgl/rig
export NODECO='mkdir -p $XDG_CONFIG_HOME; printf "[org.kde.kdecoration2]\nNoPlugin=true\n" > $XDG_CONFIG_HOME/kwinrc'
for i in 1 2; do env IMG=qtgl-run:final NAME=g-kub-gpu-$i PRE="$NODECO" FREEZE_AT=40 FREEZE_SECONDS=14 WAIT=5 STATIC_ONLY=1 SHIM=/w/kubrick-shim2.so CMD="/usr/games/kubrick --stereo" ./drun.sh >/dev/null 2>&1; done
for i in 1 2; do env IMG=qtgl-run:dbg NAME=h-kub-sw-$i SOFT=1 PRE="$NODECO" FREEZE_AT=40 FREEZE_SECONDS=14 WAIT=5 STATIC_ONLY=1 SHIM=/w/kubrick-shim2.so CMD="/usr/games/kubrick --stereo" ./drun.sh >/dev/null 2>&1; done
for i in 1 2; do env IMG=qtgl-run:dbg NAME=h-kub-gpu-$i PRE="$NODECO" FREEZE_AT=40 FREEZE_SECONDS=14 WAIT=5 STATIC_ONLY=1 SHIM=/w/kubrick-shim2.so CMD="/usr/games/kubrick --stereo" ./drun.sh >/dev/null 2>&1; done
for c in g-kub-sw-1 g-kub-sw-2 g-kub-sw-3 g-kub-gpu-1 g-kub-gpu-2 h-kub-sw-1 h-kub-sw-2 h-kub-gpu-1 h-kub-gpu-2; do OX=3 python3 an-kub.py ../ev/$c 5 > ../ev/$c/analysis.txt 2>&1; echo "$c: $(grep -E 'GL viewport' ../ev/$c/analysis.txt | cut -c1-80) | $(grep -E 'measured - predicted' ../ev/$c/analysis.txt) | $(grep -E 'near \(' ../ev/$c/analysis.txt)"; done
echo KUB_DONE
