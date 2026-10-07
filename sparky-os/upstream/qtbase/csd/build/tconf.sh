set -e
cd /work/tsrc
dpkg-source --before-build . 2>&1 | tail -2
grep -c "give a stereo\|contentEyes" src/plugins/platforms/wayland/plugins/hardwareintegration/wayland-egl/qwaylandeglwindow_p.h || true
cmake -S . -B /work/tbuild -G Ninja -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_TESTS=ON -DQT_BUILD_TESTS_BY_DEFAULT=OFF -DQT_BUILD_EXAMPLES=OFF \
  -DFEATURE_sql=OFF -DFEATURE_printsupport=OFF -DFEATURE_cups=OFF -DFEATURE_gtk3=OFF -DFEATURE_system_sqlite=OFF \
  -DFEATURE_testlib=ON -DFEATURE_wayland=ON -DFEATURE_opengl=ON -DFEATURE_dbus=ON > /work/tconf.log 2>&1 || { tail -30 /work/tconf.log; exit 1; }
tail -3 /work/tconf.log
cd /work/tbuild && ninja -t targets all | grep -E '^tst_(client|clientextension|cursor|datadevicev1|fullscreenshellv1|inputcontext|multithreaded|nooutput|output|primaryselectionv1|reconnect|scaling|seat|seatv4|seatv7|surface|tabletv2|wl_connect|xdgdecorationv1|xdgoutput|xdgshell)' | grep -v '/' | cut -d: -f1 | tr '\n' ' ' > /work/ttargets.txt; cat /work/ttargets.txt
