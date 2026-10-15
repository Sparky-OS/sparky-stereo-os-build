# Headless Stereo KWin (the edition's packages) plus Monado's build dependencies, the OpenXR
# loader and headers, lavapipe, and the ScreenShot2 capture client the edition's proof rigs use.
FROM debian:testing AS cap
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update >/dev/null && apt-get -y install --no-install-recommends g++ pkgconf qt6-base-dev >/dev/null 2>&1
COPY capture.cpp /src/capture.cpp
RUN g++ -std=c++17 -fPIC -o /capture /src/capture.cpp $(pkg-config --cflags --libs Qt6Gui Qt6DBus)

FROM debian:testing
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update >/dev/null && apt-get -y install ca-certificates >/dev/null 2>&1
RUN apt-get -y update >/dev/null && apt-get -y install --no-install-recommends build-essential debhelper cmake glslang-tools libavcodec-dev libbsd-dev libcjson-dev libdbus-1-dev libegl1-mesa-dev libeigen3-dev libgl-dev libglvnd-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libhidapi-dev libopencv-dev libsystemd-dev libsdl2-dev libudev-dev libusb-1.0-0-dev libuvc-dev libv4l-dev libvulkan-dev libwayland-dev libx11-dev libx11-xcb-dev libxcb-randr0-dev libxrandr-dev libxxf86vm-dev pkg-config wayland-protocols 2>&1 | tail -1
RUN apt-get -y install --no-install-recommends \
      libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 mesa-libgallium mesa-vulkan-drivers libvulkan1 vulkan-tools \
      libgl1 libglx0 libegl1 libgles2 libopengl0 x11-utils xauth dbus dbus-daemon dbus-x11 \
      libqt6widgets6 libqt6dbus6 libqt6gui6 qt6-wayland qt6-qpa-plugins libxcb-cursor0 \
      libwayland-client0 libxkbcommon0 libxkbcommon-x11-0 libasound2t64 libx11-6 libxcb1 libxcursor1 libxi6 libxrandr2 libxrender1 libxfixes3 libxinerama1 libxext6 \
      libopenxr-loader1 libopenxr-dev libopenxr-utils libsdl2-2.0-0 libsdl2-dev ninja-build git \
      fonts-dejavu-core python3 python3-pil python3-numpy procps 2>&1 | tail -1
RUN --mount=type=bind,from=repo,target=/repo echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/zrepo.list \
 && printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/sparky-stereo \
 && apt-get -y update 2>&1 | tail -1 \
 && apt-get -y install --no-install-recommends kwin-wayland kwin-common kwin-data xwayland libstereo-declare1 libstereo-declare-dev libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 mesa-libgallium mesa-vulkan-drivers 2>&1 | tail -3 \
 && rm -f /etc/apt/sources.list.d/zrepo.list
COPY --from=cap /capture /usr/local/bin/capture
