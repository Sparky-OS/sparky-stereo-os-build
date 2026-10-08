cd /qtgl/build-deb
ninja -j4 Core Gui Widgets OpenGL OpenGLWidgets DBus Network Xml Concurrent Sql WaylandClient qwayland qt-plugin-wayland-egl xdg-shell > /qtgl/builddeb2.log 2>&1
echo "rc=$?" >> /qtgl/builddeb2.log
