FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update >/dev/null && apt-get -y install ca-certificates >/dev/null 2>&1
COPY deb-multimedia-keyring.pgp /usr/share/keyrings/
COPY dmo.sources /etc/apt/sources.list.d/dmo.sources
RUN --mount=type=bind,from=repo,target=/repo echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/zrepo.list \
 && apt-get -y update 2>&1 | tail -3 \
 && apt-get -y install kwin-wayland=4:6.7.4-2+stereo3d13+1 xwayland=2:24.1.13-1+stereo3d1 libgl1-mesa-dri=26.1.6-1+stereo3d7 libglx-mesa0=26.1.6-1+stereo3d7 libegl-mesa0 libgbm1 mesa-utils x11-utils dbus python3 python3-pil python3-numpy libstereo-declare1 fonts-dejavu-core 2>&1 | tail -3 \
 && apt-get -y install bino 2>&1 | tail -4; apt-cache policy bino ffmpeg libavformat63 | head -30; dpkg -l | grep -E "^ii  (bino|kwin-wayland|xwayland|libglx-mesa0|libqt6gui6|libavformat|libqt6multimedia6) "; rm -f /etc/apt/sources.list.d/zrepo.list
