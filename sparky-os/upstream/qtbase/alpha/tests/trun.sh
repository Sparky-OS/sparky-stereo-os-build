# usage: trun.sh <tag>   the Wayland client autotests (qtbase's mock compositor), then the widgets tests that touch translucency
export XDG_RUNTIME_DIR=/tmp/rt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export QT_PLUGIN_PATH=/work/tbuild/plugins LANG=C.UTF-8 HOME=/tmp/h
mkdir -p $HOME
cd /work/tbuild
tag=$1
QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION= ctest --timeout 120 -j2 -R '^tst_(client|clientextension|datadevicev1|inputcontext|multithreaded|nooutput|output|primaryselectionv1|scaling|seat|seatv4|seatv7|surface|tabletv2|xdgdecorationv1|xdgoutput|xdgshell|client_fullscreenshellv1)$' -V > /work/ctest-$tag.log 2>&1
echo "ctest rc=$?" >> /work/ctest-$tag.log
tail -8 /work/ctest-$tag.log | cut -c1-200
# widgets: the translucency cases, offscreen platform (headless)
cd /work/tbuild/tests/auto/widgets/kernel/qwidget && QT_QPA_PLATFORM=offscreen timeout 600 ./tst_qwidget translucentWidget translucentWidgetDeepFormat > /work/qwidget-$tag.log 2>&1; echo "tst_qwidget rc=$?" >> /work/qwidget-$tag.log; tail -12 /work/qwidget-$tag.log | cut -c1-200
cd /work/tbuild/tests/auto/widgets/widgets/qopenglwidget && QT_QPA_PLATFORM=offscreen timeout 900 ./tst_qopenglwidget > /work/qopenglwidget-$tag.log 2>&1; echo "tst_qopenglwidget rc=$?" >> /work/qopenglwidget-$tag.log; tail -6 /work/qopenglwidget-$tag.log | cut -c1-200
