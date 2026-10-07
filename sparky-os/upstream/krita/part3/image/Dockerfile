# Proof image: fresh debian:testing + the dev repository (pinned), our KWin/Xwayland/Mesa stack, Breeze (server-side
# decorations), Qt 6 runtime from the repository, Bino, Kubrick, KAlgebra, the Qt test programs compiled in.
FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update >/dev/null && apt-get -y install ca-certificates >/dev/null 2>&1
RUN --mount=type=bind,from=repo,target=/repo echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/zrepo.list \
 && printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/sparky-stereo \
 && apt-get -y update 2>&1 | tail -1 \
 && apt-get -y install --no-install-recommends \
      kwin-wayland kwin-common kwin-data xwayland libstereo-declare1 breeze \
      libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 mesa-libgallium mesa-vulkan-drivers mesa-vulkan-layer-stereo \
      libgl1 libglx0 libegl1 libgles2 libopengl0 mesa-utils x11-utils x11-xserver-utils dbus dbus-daemon \
      libqt6widgets6 libqt6openglwidgets6 libqt6opengl6 libqt6dbus6 libqt6gui6 qt6-wayland qt6-qpa-plugins libxcb-cursor0 qt6-base-dev \
      bino kubrick kalgebra fonts-dejavu-core python3 python3-pil python3-numpy \
      gcc g++ libc6-dev pkg-config make procps 2>&1 | tail -3 \
 && dpkg-query -W kwin-wayland xwayland libgl1-mesa-dri libgbm1 mesa-libgallium bino kubrick kalgebra breeze libqt6gui6 libqt6waylandclient6 libqt6core6t64 \
 && apt-cache policy libqt6gui6 | head -4 \
 && rm -f /etc/apt/sources.list.d/zrepo.list
COPY kubrick-capture.cpp qt-stereo-test.cpp qt-plain.cpp /tmp/
RUN cd /tmp && g++ -fPIC -O1 -o /usr/local/bin/capture kubrick-capture.cpp $(pkg-config --cflags --libs Qt6Gui Qt6DBus) \
 && g++ -fPIC -O1 -o /usr/local/bin/qt-stereo-test qt-stereo-test.cpp $(pkg-config --cflags --libs Qt6Widgets Qt6OpenGLWidgets Qt6OpenGL Qt6Gui) \
 && g++ -fPIC -O1 -o /usr/local/bin/qt-plain qt-plain.cpp $(pkg-config --cflags --libs Qt6Widgets Qt6Gui) && ls -la /usr/local/bin
COPY p3test.cpp /tmp/
RUN cd /tmp && g++ -fPIC -O1 -o /usr/local/bin/p3test p3test.cpp $(pkg-config --cflags --libs Qt6Widgets Qt6OpenGLWidgets Qt6OpenGL Qt6Gui)
