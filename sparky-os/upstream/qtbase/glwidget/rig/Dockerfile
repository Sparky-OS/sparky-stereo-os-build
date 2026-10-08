# Proof image: debian:testing + the dev repository (context "repo"), headless KWin/Mesa from the repository,
# the edition's Qt (or Debian's, when the repository context has no qt6-base debs), Kubrick, KAlgebra, Kalzium, test programs.
FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update >/dev/null && apt-get -y install ca-certificates >/dev/null 2>&1
RUN --mount=type=bind,from=repo,target=/repo echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/zrepo.list \
 && printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/sparky-stereo \
 && apt-get -y update 2>&1 | tail -1 \
 && apt-get -y install --no-install-recommends \
      kwin-wayland kwin-common kwin-data xwayland libstereo-declare1 breeze \
      libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 mesa-libgallium \
      libgl1 libglx0 libegl1 libgles2 libopengl0 mesa-utils x11-utils dbus dbus-daemon \
      libqt6widgets6 libqt6openglwidgets6 libqt6opengl6 libqt6dbus6 libqt6gui6 qt6-wayland qt6-qpa-plugins libxcb-cursor0 qt6-base-dev \
      kubrick kalgebra kalzium libwayland-dev faketime \
      fonts-dejavu-core python3 python3-pil python3-numpy python3-scipy procps gcc g++ libc6-dev pkg-config make 2>&1 | tail -3 \
 && dpkg-query -W kubrick kalgebra kalzium libavogadro2-1t64 kwin-wayland libgl1-mesa-dri libqt6gui6 libqt6waylandclient6 libqt6openglwidgets6 libqt6widgets6 \
 && rm -f /etc/apt/sources.list.d/zrepo.list
COPY kubrick-capture.cpp qt-stereo-test.cpp qt-plain.cpp fakeinput.c fake-input-protocol.c fake-input-client-protocol.h gl-shim.c kubrick-shim.c /tmp/src/
RUN cd /tmp/src && g++ -fPIC -O1 -o /usr/local/bin/capture kubrick-capture.cpp $(pkg-config --cflags --libs Qt6Gui Qt6DBus) \
 && g++ -fPIC -O1 -o /usr/local/bin/qt-stereo-test qt-stereo-test.cpp $(pkg-config --cflags --libs Qt6Widgets Qt6OpenGLWidgets Qt6OpenGL Qt6Gui) \
 && g++ -fPIC -O1 -o /usr/local/bin/qt-plain qt-plain.cpp $(pkg-config --cflags --libs Qt6Widgets Qt6Gui) \
 && gcc -O1 -o /usr/local/bin/fakeinput fakeinput.c fake-input-protocol.c -lwayland-client -lm \
 && gcc -shared -fPIC -O1 -o /usr/local/lib/gl-shim.so gl-shim.c -ldl \
 && gcc -shared -fPIC -O1 -o /usr/local/lib/kubrick-shim.so kubrick-shim.c -ldl \
 && ls -la /usr/local/bin /usr/local/lib/*.so
