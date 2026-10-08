set -e
cmake -S /qtgl/src -B /qtgl/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_TESTS=ON -DQT_BUILD_TESTS_BY_DEFAULT=OFF -DQT_BUILD_EXAMPLES=OFF \
  -DFEATURE_sql=OFF -DFEATURE_printsupport=OFF -DFEATURE_cups=OFF -DFEATURE_gtk3=OFF -DFEATURE_system_sqlite=OFF \
  -DFEATURE_testlib=ON -DFEATURE_wayland=ON -DFEATURE_opengl=ON -DFEATURE_dbus=ON > /qtgl/conf.log 2>&1 || { tail -30 /qtgl/conf.log; exit 1; }
cd /qtgl/build
ninja -j4 Core Gui Widgets OpenGL OpenGLWidgets DBus Network Test Xml Concurrent WaylandClient qwayland qt-plugin-wayland-egl xdg-shell  > /qtgl/build.log 2>&1
echo "rc=$?" >> /qtgl/build.log
