export XDG_RUNTIME_DIR=/tmp/rt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export QT_PLUGIN_PATH=/work/tbuild/plugins QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION= LANG=C.UTF-8 HOME=/tmp/h
mkdir -p $HOME
cd /work/tbuild
tag=$1
# the Wayland client autotests; the suite's own driver, 4 parallel jobs at most
ctest --timeout 120 -j2 -R '^tst_(client|clientextension|datadevicev1|inputcontext|multithreaded|nooutput|output|primaryselectionv1|scaling|seat|seatv4|seatv7|surface|tabletv2|xdgdecorationv1|xdgoutput|xdgshell|client_fullscreenshellv1)$' --output-on-failure > /work/ctest-$tag.log 2>&1
echo "ctest rc=$?" >> /work/ctest-$tag.log
tail -40 /work/ctest-$tag.log | cut -c1-200
