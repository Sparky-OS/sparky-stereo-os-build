cd /qtgl/build
T="tst_client tst_clientextension tst_datadevicev1 tst_client_fullscreenshellv1 tst_inputcontext tst_multithreaded tst_nooutput tst_output tst_primaryselectionv1 tst_scaling tst_seat tst_seatv4 tst_seatv7 tst_surface tst_tabletv2 tst_xdgdecorationv1 tst_xdgoutput tst_xdgshell"
ninja -j4 Core Gui Widgets OpenGL OpenGLWidgets DBus Network Test Xml Concurrent WaylandClient qwayland qt-plugin-wayland-egl xdg-shell $T tst_qwidget tst_qopenglwidget tst_qwidget_window tst_qwindowcontainer > /qtgl/tbuild-$1.log 2>&1
echo "rc=$?" >> /qtgl/tbuild-$1.log
