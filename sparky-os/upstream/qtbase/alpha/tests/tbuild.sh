set -e
cd /work/tsrc
cmake -S . -B /work/tbuild -G Ninja -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_TESTS=ON -DQT_BUILD_TESTS_BY_DEFAULT=OFF -DQT_BUILD_EXAMPLES=OFF \
  -DFEATURE_sql=OFF -DFEATURE_printsupport=OFF -DFEATURE_cups=OFF -DFEATURE_gtk3=OFF -DFEATURE_system_sqlite=OFF \
  -DFEATURE_testlib=ON -DFEATURE_wayland=ON -DFEATURE_opengl=ON -DFEATURE_dbus=ON > /work/tconf.log 2>&1 || { tail -30 /work/tconf.log; exit 1; }
cd /work/tbuild
ninja -t targets all | grep -E '^tst_(client|clientextension|datadevicev1|fullscreenshellv1|inputcontext|multithreaded|nooutput|output|primaryselectionv1|scaling|seat|seatv4|seatv7|surface|tabletv2|xdgdecorationv1|xdgoutput|xdgshell)' | grep -v '/' | cut -d: -f1 | tr '\n' ' ' > /work/ttargets.txt
T=$(tr ' ' '\n' < /work/ttargets.txt | grep -E '^tst_[a-z0-9_]+$' | grep -v -E '_(autogen|check|autogen_timestamp_deps)$' | tr '\n' ' ')
echo "targets: $T tst_qwidget tst_qopenglwidget" > /work/tbuild.log
ninja -j4 $T tst_client_fullscreenshellv1 tst_qwidget tst_qopenglwidget >> /work/tbuild.log 2>&1
echo "rc=$?" >> /work/tbuild.log
