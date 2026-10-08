# usage: trun.sh <tag>   in the Qt build container: Wayland client autotests (mock compositor), then widgets tests offscreen
export XDG_RUNTIME_DIR=/tmp/rt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export QT_PLUGIN_PATH=/qtgl/build/plugins LANG=C.UTF-8 HOME=/tmp/h
mkdir -p $HOME /qtgl/tres
cd /qtgl/build
tag=$1
QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION= ctest --timeout 120 -j2 -R '^tst_(client|clientextension|datadevicev1|inputcontext|multithreaded|nooutput|output|primaryselectionv1|scaling|seat|seatv4|seatv7|surface|tabletv2|xdgdecorationv1|xdgoutput|xdgshell|client_fullscreenshellv1)$' -V > /qtgl/tres/ctest-$tag.log 2>&1
echo "ctest rc=$?" >> /qtgl/tres/ctest-$tag.log
tail -4 /qtgl/tres/ctest-$tag.log | head -2
for t in "widgets/kernel/qwidget tst_qwidget" "widgets/kernel/qwidget_window tst_qwidget_window" "widgets/kernel/qwindowcontainer tst_qwindowcontainer" "widgets/widgets/qopenglwidget tst_qopenglwidget"; do
  set -- $t
  cd /qtgl/build/tests/auto/$1 && QT_QPA_PLATFORM=offscreen timeout 1500 ./$2 > /qtgl/tres/$2-$tag.log 2>&1; echo "$2 rc=$?" >> /qtgl/tres/$2-$tag.log
  echo "$2: $(grep -E '^Totals:' /qtgl/tres/$2-$tag.log) rc=$(tail -1 /qtgl/tres/$2-$tag.log)"
done
